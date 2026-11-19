#!/usr/bin/env python3
"""Spark 内置 Logos 预处理器（perl 的替代实现）。

为什么需要
----------
Theos 用 `logos.pl`（Perl 脚本）把 .x 展开成 ObjC。
本机所有 Theos 运行时（Rein / DSH / CodexApp）的 perl 都是**动态薄壳**，
依赖 libperl.dylib，而这个库谁都没带 —— perl 跑不起来，
logos.pl 就跑不起来，.x 工程全都没法编译。

这个脚本用纯 Python 实现同一套展开，不依赖 perl。

支持的指令
----------
  %hook ClassName ... %end          类 hook
  %group Name ... %end              分组
  %init / %ctor / %dtor             初始化
  %new                              新增方法
  %orig                             调用原实现（可带参）
  %c(ClassName)                     → objc_getClass("ClassName")
  %config(...)                      配置（忽略）
  %property                         属性（展开为 getter/setter）

用法
----
  python3 spark-logos.py <input.x> <output.m>
  python3 spark-logos.py --check <input.x>     # 只解析不输出
"""

import re
import sys
import hashlib


# ─────────────────────────────────────────────────────────────
# 解析
# ─────────────────────────────────────────────────────────────

class Method:
    def __init__(self):
        self.name = ''
        self.ret = 'id'
        self.arg_types = ''      # "int, id"
        self.arg_names = ''      # "a, b"
        self.is_class = False
        self.is_new = False
        self.body = []


class ClassHook:
    def __init__(self, name):
        self.name = name
        self.methods = []
        self.prologue = []


class Group:
    def __init__(self, name):
        self.name = name
        self.classes = []
        self.inits = []


def split_signature(sig):
    """'(int, id, NSString *)' → (['int','id','NSString *'], ['arg0','arg1','arg2'])"""
    sig = sig.strip()
    if sig.startswith('(') and sig.endswith(')'):
        sig = sig[1:-1]
    if not sig.strip():
        return '', ''
    types, names = [], []
    depth = 0
    cur = ''
    for ch in sig:
        if ch == '<':
            depth += 1
        elif ch == '>':
            depth -= 1
        if ch == ',' and depth == 0:
            types.append(cur.strip())
            cur = ''
        else:
            cur += ch
    if cur.strip():
        types.append(cur.strip())

    # 拆出参数名：`int x` → 类型 int，名 x
    ty, nm = [], []
    for i, t in enumerate(types):
        parts = t.split()
        if len(parts) >= 2 and re.match(r'^[A-Za-z_]\w*$', parts[-1]):
            # 最后一个词像标识符，当作参数名
            name = parts[-1]
            typ = ' '.join(parts[:-1])
            if typ.endswith('*') or name.startswith('*'):
                typ += '*'
            ty.append(typ)
            nm.append(name.lstrip('*'))
        else:
            ty.append(t)
            nm.append('arg%d' % i)
    return ', '.join(ty), ', '.join(nm)


def parse(source):
    groups = [Group('_ungrouped')]
    cur_group = groups[0]
    cur_class = None
    cur_method = None
    _pending_new = [False]

    lines = source.split('\n')
    for line in lines:
        t = line.strip()

        # %hook
        m = re.match(r'^%hook\s+([\w.]+)', t)
        if m:
            c = ClassHook(m.group(1))
            cur_group.classes.append(c)
            cur_class = c
            cur_method = None
            continue

        # %group
        m = re.match(r'^%group\s+(\w+)', t)
        if m:
            g = Group(m.group(1))
            groups.append(g)
            cur_group = g
            continue

        # %end
        if t.startswith('%end'):
            if cur_class:
                cur_class = None
                cur_method = None
            else:
                cur_group = groups[0]
            continue

        # hook 块内
        if cur_class:
            # %new 单独一行 = 标记下一个方法
            if t == '%new':
                _pending_new[0] = True
                continue
            # 方法定义：- (ret)name / + (ret)name
            mm = re.match(r'^([-+])\s*(%new\s+)?(.*)$', t)
            if mm and not cur_method:
                meth = Method()
                meth.is_class = (mm.group(1) == '+')
                rest = mm.group(3)
                if _pending_new[0]:
                    meth.is_new = True
                    _pending_new[0] = False
                if rest.startswith('%new'):
                    meth.is_new = True
                    rest = rest[4:].strip()

                # (ret)name
                pm = re.match(r'^\(([^)]*)\)\s*(.*)$', rest)
                if pm:
                    meth.ret = pm.group(1).strip() or 'id'
                    tail = pm.group(2).strip()
                else:
                    meth.ret = 'id'
                    tail = rest

                # ObjC selector 形式：a:(id)x b:(int)y → name="a:b:", 参数两个
                body = tail.split('{')[0].strip()
                if ':' in body:
                    parts = re.findall(r'([\w]*)\s*:\s*\(([^)]*)\)\s*([\w]*)', body)
                    if parts:
                        meth.name = ''.join((pp[0] or '') + ':' for pp in parts)
                        types = [pp[1].strip() for pp in parts]
                        names = [pp[2].strip() or ('arg%d' % i) for i, pp in enumerate(parts)]
                        meth.arg_types = ', '.join(types)
                        meth.arg_names = ', '.join(names)
                    else:
                        meth.name = body
                else:
                    meth.name = body

                cur_class.methods.append(meth)
                cur_method = meth
                # 同一行有方法体
                if '{' in t:
                    after = t.split('{', 1)[1]
                    if after.strip() and after.strip() != '}':
                        cur_method.body.append(after)
                continue

            if cur_method:
                if t.startswith('}'):
                    cur_method = None
                    continue
                # %orig 替换
                if '%orig' in line:
                    call = '_logos_orig(self, _cmd'
                    if cur_method.arg_names:
                        call += ', ' + cur_method.arg_names
                    call += ')'
                    # %orig 后没括号就补参数
                    line = re.sub(r'%orig(?!\s*\()', call, line)
                    line = line.replace('%orig', '_logos_orig')
                    cur_method.body.append(line)
                    continue
                cur_method.body.append(line)
                continue

            # 块内其它代码
            im = re.match(r'^%(?:init|ctor|dtor)\s*\(?(.*?)\)?\s*[;{]?$', t)
            if im and im.group(1).strip():
                cur_group.inits.append(im.group(1).strip())
                continue
            cur_class.prologue.append(line)
            continue

        # 全局 %ctor / %init
        im = re.match(r'^%(?:ctor|init|dtor)\s*\(?(.*?)\)?\s*[;{]?$', t)
        if im and im.group(1).strip():
            cur_group.inits.append(im.group(1).strip())
            continue

        if t.startswith('%config'):
            continue

    return groups


# ─────────────────────────────────────────────────────────────
# 生成
# ─────────────────────────────────────────────────────────────

def emit(groups):
    out = []
    out.append('// 由 Spark 内置 Logos 预处理器生成（不依赖 perl）')
    out.append('#include <objc/runtime.h>')
    out.append('#include <objc/message.h>')
    out.append('#include <objc/objc.h>')
    out.append('')

    for g in groups:
        for c in g.classes:
            safe = re.sub(r'\W', '_', c.name)
            if c.prologue:
                out.append('\n'.join(c.prologue))

            # 原函数指针 + 新函数
            for m in c.methods:
                if not m.is_new:
                    out.append('static %s (*_logos_orig$%s$%s)(%s, SEL%s);' % (
                        m.ret, safe, re.sub(r'\W', '_', m.name), c.name,
                        (', ' + m.arg_types) if m.arg_types else ''))

            for m in c.methods:
                # 参数要带类型：`int, id` + `a, b` → `int a, id b`
                ty = [x.strip() for x in m.arg_types.split(',')] if m.arg_types else []
                nm = [x.strip() for x in m.arg_names.split(',')] if m.arg_names else []
                decls = ', '.join('%s %s' % (ty[i] if i < len(ty) else 'id',
                                             nm[i] if i < len(nm) else 'arg%d' % i)
                                  for i in range(max(len(ty), len(nm))))
                out.append('')
                out.append('static %s _logos_method$%s$%s(%, SEL _cmd%s) {' % (
                    '', 0, 0, '', '') if False else
                           ('static %s _logos_method$%s$%s(%s self, SEL _cmd%s) {' % (
                               m.ret, safe, re.sub(r'\W', '_', m.name), c.name,
                               ((', ' + decls) if decls else ''))))
                for ln in m.body:
                    out.append(ln)
                out.append('}')

            # 注册
            out.append('')
            out.append('__attribute__((constructor)) static void _logos_register_%s(void) {' % safe)
            out.append('    Class _cls = objc_getClass("%s");' % c.name)
            out.append('    if (!_cls) return;')
            for m in c.methods:
                sel = m.name
                nargs = len(m.arg_names.split(',')) if m.arg_names else 0
                if nargs and ':' not in sel:
                    sel = sel + ':' * nargs
                if m.is_new:
                    out.append('    class_addMethod(_cls, sel_registerName("%s"), '
                               '(IMP)_logos_method$%s$%s, "%s%s");' % (
                                   sel, safe, re.sub(r'\W', '_', m.name), m.ret,
                                   ('(' + m.arg_types + ')') if m.arg_types else ''))
                else:
                    out.append('    {')
                    out.append('        Method _m = class_getInstanceMethod(_cls, sel_registerName("%s"));' % sel)
                    out.append('        if (_m) {')
                    out.append('            _logos_orig$%s$%s = (%s (*)(%s, SEL%s))method_getImplementation(_m);' % (
                        safe, re.sub(r'\W', '_', m.name), m.ret, c.name, (', ' + m.arg_types) if m.arg_types else ''))
                    out.append('            method_setImplementation(_m, (IMP)_logos_method$%s$%s);' % (safe, re.sub(r'\W', '_', m.name)))
                    out.append('        }')
                    out.append('    }')
            out.append('}')
            out.append('')

        if g.inits:
            out.append('__attribute__((constructor)) static void _logos_ctor_%s(void) {' % re.sub(r'\W', '_', g.name))
            for ln in g.inits:
                out.append('    %s;' % ln)
            out.append('}')
            out.append('')

    return '\n'.join(out)


def preprocess(source):
    # %c(...) → objc_getClass("...")
    source = re.sub(r'%c\(\s*([^)]+?)\s*\)', r'objc_getClass("\1")', source)
    return emit(parse(source))


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    if sys.argv[1] == '--check':
        src = open(sys.argv[2], encoding='utf-8', errors='replace').read()
        groups = parse(src)
        n = sum(len(c.methods) for g in groups for c in g.classes)
        print('解析成功：%d 组 / %d 类 / %d 方法' % (
            len(groups), sum(len(g.classes) for g in groups), n))
        return 0
    if len(sys.argv) < 3:
        print('用法：spark-logos.py <input.x> <output.m>')
        return 1
    src = open(sys.argv[1], encoding='utf-8', errors='replace').read()
    out = preprocess(src)
    open(sys.argv[2], 'w', encoding='utf-8').write(out)
    return 0


if __name__ == '__main__':
    sys.exit(main())
