#!/usr/bin/env python3
"""Logos 预处理器的回归测试。"""
import subprocess, sys, tempfile, os

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
""", ['_logos_method$NSObject$load']),

    ("多参数", """
%hook Foo
- (void)a:(id)x b:(int)y { %orig; }
%end
""", ['sel_registerName("a:b:")']),

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
        print('  ✗ %s（解析失败）' % name); fails += 1; continue
    got = open(out).read()
    miss = [e for e in expects if e not in got]
    if miss:
        print('  ✗ %s（缺 %s）' % (name, miss)); fails += 1
    else:
        print('  ✓ %s' % name)
    os.unlink(inp); os.unlink(out)

print('失败 %d / %d' % (fails, len(CASES)))
sys.exit(1 if fails else 0)
