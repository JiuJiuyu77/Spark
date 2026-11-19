#!/usr/bin/env python3
"""Logos 预处理器的回归测试。"""
import subprocess, sys, tempfile, os, re

TOOL = os.path.join(os.path.dirname(__file__), '..', 'tools', 'spark-logos.py')

CASES = [
    ("基础 hook + %orig", """
%hook SpringBoard
- (void)foo { %orig; }
%end
""", ['_logos_register_SpringBoard', 'method_setImplementation', '_logos_orig']),

    ("%new 方法", """
%hook NSObject
%new
- (void)hello { }
%end
""", ['class_addMethod']),

    ("类方法 +", """
%hook NSObject
+ (void)load { %orig; }
%end
""", ['_logos_method_NSObject_load']),

    ("多参数", """
%hook Foo
- (void)a:(id)x b:(int)y { %orig; }
%end
""", ['sel_registerName("a:b:")']),

    ("%group + %init", """
%group G
%hook Foo
- (void)a { %orig; }
%end
%end
%ctor { %init(G); }
""", ['_logos_register_G();']),

    ("%c 展开", """
%hook Foo
- (void)x { Class c = %c(NSObject); }
%end
""", ['objc_getClass("NSObject")']),
]

fails = 0
for name, src, expects in CASES:
    with tempfile.NamedTemporaryFile('w', suffix='.x', delete=False) as f:
        f.write(src); inp = f.name
    out = inp + '.m'
    r = subprocess.run([sys.executable, TOOL, inp, out], capture_output=True)
    if r.returncode != 0:
        print('  ✗ %s（解析失败）' % name); fails += 1
        os.unlink(inp); continue
    got = open(out).read()

    # C 标识符不允许 $，出现过就说明符号拼接有 bug
    if '$' in got:
        print('  ✗ %s（生成了含 $ 的非法标识符）' % name); fails += 1
        os.unlink(inp); os.unlink(out); continue

    # 不能出现裸标识符语句（如 MyGroup;）
    bad = re.findall(r'^\s+[A-Z][A-Za-z0-9_]*;\s*$', got, re.M)
    if bad:
        print('  ✗ %s（出现非法语句 %s）' % (name, bad[:2])); fails += 1
        os.unlink(inp); os.unlink(out); continue

    miss = [e for e in expects if e not in got]
    if miss:
        print('  ✗ %s（缺 %s）' % (name, miss)); fails += 1
    else:
        print('  ✓ %s' % name)
    os.unlink(inp); os.unlink(out)

print('失败 %d / %d' % (fails, len(CASES)))
sys.exit(1 if fails else 0)
