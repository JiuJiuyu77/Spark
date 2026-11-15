#!/usr/bin/env python3
"""检查 .m 里用到的 SP* 类有没有直接 #import 它的头文件。

没有 macOS 也能拦掉「use of undeclared identifier」这类错误 —— CI 上
一次 macOS 构建要等十分钟，这种低级错误不该靠它来发现。
"""
import glob
import os
import re
import sys

SRC = 'Native/ObjC'


def load_declarations():
    """类名 -> 声明它的头文件集合"""
    decl = {}
    for h in glob.glob(os.path.join(SRC, '*.h')):
        text = open(h, encoding='utf-8').read()
        for name in re.findall(r'@interface\s+(\w+)', text):
            decl.setdefault(name, set()).add(os.path.basename(h))
    return decl


def reachable_classes(imported, decl, cache):
    """已导入的头文件能看到的类（含再导出）"""
    seen_classes = set()
    for header in imported:
        path = os.path.join(SRC, header)
        if not os.path.exists(path):
            continue
        if header not in cache:
            cache[header] = open(path, encoding='utf-8').read()
        text = cache[header]
        seen_classes |= set(re.findall(r'@interface\s+(\w+)', text))
        for nested in re.findall(r'#import\s+"(\w+\.h)"', text):
            seen_classes |= reachable_classes({nested}, decl, cache)
    return seen_classes


def main():
    decl = load_declarations()
    cache = {}
    problems = []

    for m in sorted(glob.glob(os.path.join(SRC, '*.m'))):
        text = open(m, encoding='utf-8').read()
        own = set(re.findall(r'@interface\s+(\w+)', text))
        imported = set(re.findall(r'#import\s+"(\w+\.h)"', text))
        visible = reachable_classes(imported, decl, cache) | own

        for used in sorted(set(re.findall(r'\b(SP[A-Z]\w+)\b', text))):
            if used not in decl or used in visible:
                continue
            problems.append(
                f'{os.path.basename(m)}: 使用 {used} 但没有 #import {"/".join(sorted(decl[used]))}'
            )

    # 顺带检查重复 import
    for m in sorted(glob.glob(os.path.join(SRC, '*.m'))):
        imports = re.findall(r'#import\s+"(\w+\.h)"', open(m, encoding='utf-8').read())
        dup = {h for h in imports if imports.count(h) > 1}
        for h in sorted(dup):
            problems.append(f'{os.path.basename(m)}: 重复 #import "{h}"')

    if problems:
        print('发现 %d 个导入问题：' % len(problems))
        for p in problems:
            print('  ' + p)
        return 1

    print(f'导入检查通过（{len(glob.glob(os.path.join(SRC, "*.m")))} 个 .m）')
    return 0


if __name__ == '__main__':
    sys.exit(main())
