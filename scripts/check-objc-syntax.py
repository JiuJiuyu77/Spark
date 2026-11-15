#!/usr/bin/env python3
"""扫描 Objective-C 里几类「语法上不合法、但很容易写出来」的写法。

都是本项目真实踩过的坑：
  1. 点语法带参数：scan.pathFor(x)  —— ObjC 没有这种语法，必须 [scan pathFor:x]
  2. 数组/字典字面量直接下标：@[@1,@2][i]  —— 字面量不是左值，先赋给变量
  3. 三元表达式当消息接收者：[self foo:a ? b : c message:d]  —— 必须加括号
  4. &self.property  —— ARC 下取属性地址非法，用局部变量中转
  5. switch 里 case 直接声明变量 —— 必须加花括号包住作用域
"""
import glob
import os
import re
import sys

SRC = 'Native/ObjC'

# 明显不存在的系统方法调用（本仓库踩过的坑，避免再犯）
KNOWN_BAD = [
    ('[UIColor', 'setTintColor', 'UIColor 没有 setTintColor，tintColor 是 UIView/UIImage 的属性'),
    ('CALayer', '.strokeColor', 'CALayer 没有 strokeColor，用 CAShapeLayer'),
    ('CALayer', '.fillColor', 'CALayer 没有 fillColor，用 CAShapeLayer'),
    ('CAGradientLayer', 'strokeColor', 'CAGradientLayer 不支持描边，用 CAShapeLayer'),
    ('NSUserDefaults', 'integerValueForKey', 'NSUserDefaults 用 integerForKey:'),
]
PROBLEMS = []


def strip_noise(text: str) -> str:
    out = []
    i, n = 0, len(text)
    while i < n:
        if text.startswith('//', i):
            j = text.find('\n', i)
            i = n if j < 0 else j
            continue
        if text.startswith('/*', i):
            j = text.find('*/', i + 2)
            i = n if j < 0 else j + 2
            continue
        c = text[i]
        if c == '"':
            out.append('""')
            i += 1
            while i < n:
                if text[i] == '\\':
                    i += 2
                    continue
                if text[i] == '"':
                    i += 1
                    break
                i += 1
            continue
        out.append(c)
        i += 1
    return ''.join(out)


def check(path: str):
    raw = open(path, encoding='utf-8').read()
    text = strip_noise(raw)
    name = os.path.basename(path)
    lines = text.split('\n')

    for lineno, line in enumerate(lines, 1):
        # 1. 点语法带参数（排除 block 调用 self.onXxx(a) 与 [] 下标）
        # 接收者不取 self（self.onXxx(...) 是 block 调用），正则用负向后顾排除
        for m in re.finditer(r'(?<![\w.])([a-zA-Z_]\w*(?:\.\w+)*)\.([a-zA-Z_]\w*)\s*\(', line):
            obj, sel = m.group(1), m.group(2)
            # 接收者以 self. 开头的一律跳过（block 属性调用）
            if obj.startswith('self'):
                continue
            # self.onXxx(...) / self.<blockName>(...) 都是调用 block 属性，合法。
            # 真正要拦的是「接收者是对象」的情况，如 scan.pathFor(x)。
            if obj.startswith('self.'):
                continue
            if obj in ('dispatch_async', 'dispatch_after', 'dispatch_once', 'dispatch_group_notify'):
                continue
            # 排除 NSTimer scheduledTimerWithTimeInterval:block:^(NSTimer *t) 这类
            if re.search(re.escape(m.group(0)) + r'\s*\^', line):
                continue
            PROBLEMS.append(f'{name}:{lineno}: 点语法带参数 `{obj}.{sel}(` → 应写 `[{obj} {sel}:...]`')

        # 2. 字面量直接下标
        if re.search(r'@\[[^\]]*\]\s*\[[\w.]+\]', line):
            PROBLEMS.append(f'{name}:{lineno}: 字面量直接下标 `@[...][i]` → 先赋给变量')
        if re.search(r'@\{[^}]*\}\s*\[', line):
            PROBLEMS.append(f'{name}:{lineno}: 字面量直接下标 `@{...}[k]` → 先赋给变量')

        # 4. &self.property
        if re.search(r'&\s*self\.\w+\s*[,)]', line) and '&self.' in line:
            PROBLEMS.append(f'{name}:{lineno}: 取属性地址 `&self.xxx` → ARC 下非法，用局部变量')

    # 3. 三元当接收者：[receiver a ? b : c selector:...]
    for lineno, line in enumerate(lines, 1):
        # 只认「[receiver 第一段: 条件 ? x : y 第二段:」这种真正的歧义写法
        # 真正的歧义：[recv sel: cond ? a : b sel2:   —— 三元里必须没有括号包裹
        if '?:' in line:
            pass
        m = re.search(r'\[\s*[\w.]+\s+[A-Za-z]\w*:\s*[^:()\[\]]+\?[^:()\[\]]+:\s*[^:()\[\]\s][^:()\[\]]*\s+[A-Za-z]\w*:', line)
        if m:
            PROBLEMS.append(f'{name}:{lineno}: 三元表达式当消息接收者 → 用括号包起来')

    # 4b. 已知不存在的系统方法
    for lineno, line in enumerate(lines, 1):
        # 方括号后残留属性访问：[self.view addSubview:self].table
        if re.search(r'\[\s*self\.[\w.]+\s+addSubview:[\w.]+\]\s*\.', line):
            PROBLEMS.append(f'{name}:{lineno}: addSubview 后多了 .属性，应写 [self.view addSubview:view]')
        for owner, member, hint in KNOWN_BAD:
            if owner in line and member in line:
                PROBLEMS.append(f'{name}:{lineno}: {hint}')

    # 5. switch 里 case 直接声明变量（粗略：case 行末尾声明且下一个 case 前没有 {）
    in_switch = False
    depth = 0
    for lineno, line in enumerate(lines, 1):
        if re.search(r'\bswitch\s*\(', line):
            in_switch = True
            depth = 0
        if not in_switch:
            continue
        depth += line.count('{') - line.count('}')
        m = re.match(r'\s*case\s+[^:]+:\s*(\{)?\s*(.+)$', line)
        if m and not m.group(1):
            body = m.group(2)
            # case 体内直接声明指针/对象变量且没包大括号
            if re.search(r'\b(NSArray|NSMutableString|NSString|NSMutableArray|NSNumber|CGFloat|NSInteger)\s*\*?\s*\w+\s*=', body):
                PROBLEMS.append(f'{name}:{lineno}: switch 的 case 内直接声明变量 → 加 {{ }} 包住作用域')
        if in_switch and depth <= 0 and line.rstrip().endswith('}'):
            in_switch = False


def main() -> int:
    files = sorted(glob.glob(os.path.join(SRC, '*.m')))
    for f in files:
        check(f)
    # 已知合法的写法（@[...][i] 编译器接受，仅告警不拦）
    soft = [x for x in PROBLEMS if '字面量直接下标' in x]
    if soft:
        print(f'⚠️  {len(soft)} 处字面量直接下标（合法但可读性差，建议先赋变量）')
    hard = [x for x in PROBLEMS if '字面量直接下标' not in x]
    PROBLEMS[:] = hard
    if PROBLEMS:
        print(f'发现 {len(PROBLEMS)} 处可疑写法：')
        for p in PROBLEMS:
            print('  ' + p)
        return 1
    print(f'ObjC 语法陷阱检查通过（{len(files)} 个 .m）')
    return 0


if __name__ == '__main__':
    sys.exit(main())
