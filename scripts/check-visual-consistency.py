#!/usr/bin/env python3
"""视觉一致性检查：禁止在页面里手写尺寸/圆角魔术数字。

为什么需要
----------
项目早期各页面各写各的：圆角 8/9/10/12/16/18/20 七种，
页边距 8/10/12/16/20/32 六种。单独看每页都还行，
放在一起就像几个人拼的 —— 这就是「UI 层级非常杂乱」的来源之一。

现在统一到 SPTheme 里的设计令牌：
    间距    SPSpaceXXS(4) XS(8) S(12) M(16) L(20) XL(24) Huge(28) XXL(32)
    圆角    SPRadiusS(8) M(12) L(16) XL(22)
    尺寸    SPIconSize* / SPButtonHeight / SPFloatingBar*

这个脚本扫描 .m，把「页边距 / 圆角」位置出现的裸数字报出来。

允许的例外（白名单）
--------------------
· 内部 1~6pt 的微调（图标内缩、分割线位置）
· 0 和负数居中约束
· 尺寸常量已用 SPIconSize* 等

用法
----
    python3 scripts/check-visual-consistency.py [目录]
"""

import glob
import os
import re
import sys

# 行内微调允许的数值（4/6 等小间距、2pt 细线）
ALLOWED_INLINE_NUMBERS = {0, 1, 2, 3, 4, 5, 6}

# 这些 anchor 的 constant 属于「页边距」语义，必须用 token
MARGIN_ANCHORS = ('leadingAnchor', 'trailingAnchor')

# 这些位置属于「圆角」语义
RADIUS_PATTERNS = [
    re.compile(r'radius:\s*(\d+)'),
    re.compile(r'cornerRadius\s*=\s*(\d+)'),
]

MARGIN_PATTERN = re.compile(
    r'(leading|trailing)Anchor\s+constant:\s*(-?\d+)')


def main() -> int:
    root = sys.argv[1] if len(sys.argv) > 1 else 'Native/ObjC'
    files = sorted(glob.glob(os.path.join(root, '*.m')))
    if not files:
        print(f'[!] {root} 下没有 .m 文件')
        return 0

    problems = []
    for path in files:
        name = os.path.basename(path)
        for lineno, line in enumerate(open(path, encoding='utf-8', errors='ignore'), 1):
            # 跳过注释行
            stripped = line.strip()
            if stripped.startswith('//') or stripped.startswith('*'):
                continue

            for pat in RADIUS_PATTERNS:
                for m in pat.finditer(line):
                    n = int(m.group(1))
                    if n in ALLOWED_INLINE_NUMBERS:
                        continue
                    problems.append(
                        f'{name}:{lineno}: 圆角用了裸数字 {n}，'
                        f'请用 SPRadiusS/M/L/XL')

            for m in MARGIN_PATTERN.finditer(line):
                n = abs(int(m.group(2)))
                if n in ALLOWED_INLINE_NUMBERS:
                    continue
                problems.append(
                    f'{name}:{lineno}: {m.group(1)} 用了裸数字 {n}，'
                    f'请用 SPSpaceXS/S/M/L/XL/XXL')

    if problems:
        print(f'[✗] {len(problems)} 处视觉尺寸未走设计令牌：')
        for p in problems[:40]:
            print('    ' + p)
        if len(problems) > 40:
            print(f'    …… 还有 {len(problems) - 40} 处')
        return 1

    print(f'[ok] 视觉一致性检查通过（{len(files)} 个文件）')
    return 0


if __name__ == '__main__':
    sys.exit(main())
