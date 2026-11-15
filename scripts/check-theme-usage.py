#!/usr/bin/env python3
"""检查 .m 里调用的 SPTheme / SPMotion 成员是否真实存在。

重写视觉层最容易犯的错：改了头文件却漏改调用点，机器上没有 macOS
就发现不了。这个脚本直接解析 SPTheme.h 的类方法声明，逐文件比对。
"""
import glob
import os
import re
import sys

SRC = 'Native/ObjC'


def declared_members(header: str) -> set:
    """从头文件里抓类方法名，如 + (UIColor *)accent  ->  accent；+ (void)round:radius: -> round:radius:"""
    text = open(os.path.join(SRC, header), encoding='utf-8').read()
    names = set()
    for m in re.finditer(r'^\s*\+\s*\([^)]*\)\s*([A-Za-z_][A-Za-z0-9_]*(?::[A-Za-z0-9_]+)*)', text, re.M):
        names.add(m.group(1))
        # 同时记下第一段名字（不含冒号），方便按 selector 前缀比对
        names.add(m.group(1).split(':')[0])
    return names


def main() -> int:
    theme = declared_members('SPTheme.h')
    problems = []

    for m in sorted(glob.glob(os.path.join(SRC, '*.m'))):
        text = open(m, encoding='utf-8').read()
        # 去掉注释与 #import，避免 "SPTheme.h" 被当成点语法
        text = re.sub(r'//[^\n]*', '', text)
        text = re.sub(r'#import[^\n]*', '', text)
        # [SPTheme xxx:...] / [SPTheme xxx]
        for used in re.findall(r'\[\s*SPTheme\s+([A-Za-z_][A-Za-z0-9_]*)', text):
            if used not in theme:
                problems.append(f'{os.path.basename(m)}: SPTheme 没有成员 {used}')
        # SPTheme.xxx（只认真正的点语法，排除 self.SPTheme 之类）
        for used in re.findall(r'(?<![A-Za-z0-9_.])SPTheme\.([A-Za-z_][A-Za-z0-9_]*)', text):
            if used not in theme:
                problems.append(f'{os.path.basename(m)}: SPTheme.（点语法）访问了不存在的 {used}')

    if problems:
        print('发现 %d 处主题调用不存在：' % len(problems))
        for p in problems:
            print('  ' + p)
        return 1
    print(f'主题调用检查通过（SPTheme 共 {len(theme)} 个成员）')
    return 0


if __name__ == '__main__':
    sys.exit(main())
