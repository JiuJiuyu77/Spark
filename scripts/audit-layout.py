#!/usr/bin/env python3
"""Auto Layout 层级审计（保守版，只报高置信度问题）。

背景
----
约束必须建立在有共同祖先的视图之间。跨树约束会让 UIKit 报
"Unable to simultaneously satisfy constraints" 并随机破坏某条约束，
表现就是「UI 层级杂乱」。

本项目真实修过的问题
--------------------
1. SPConsoleViewController：
   primaryButton 在 actionBar.contentView 里，
   但 bottom 约束到 self.view.safeAreaLayoutGuide
   → 按钮被拉出操作条
2. SPAppDelegate：
   floatBar 加到 window，却约束到 window.safeArea
   （此时 window 还没布局，safeArea 全 0）→ 底栏跑到屏幕外

设计原则：**宁可漏报，不可误报**
--------------------------------
静态分析很难完全还原视图层级（别名、局部变量、运行时创建），
误报会让人失去对工具的信心。所以这里只检测一种情况：

    约束的一方是明确的 `self.view` 的直接/间接子视图，
    另一方也是 `self.view` 的子视图，
    但两者在 addSubview 关系图里找不到共同祖先。

并且两边都必须能被追踪到，否则跳过。

用法
----
    python3 scripts/audit-layout.py [目录]

退出码
------
0 = 未发现高置信度问题
1 = 发现跨树约束
"""

import glob
import os
import re
import sys

ADD_RE = re.compile(
    r'\[\s*([\w.]+)\s+(?:addSubview|insertSubview|addArrangedSubview):'
    r'\s*([\w.]+)\s*\]')

# self.foo = localVar;  /  self.foo = otherVar;
ALIAS_RE = re.compile(r'self\.(\w+)\s*=\s*([\w.]+)\s*;')

CONSTRAINT_RE = re.compile(
    r'\[\s*(self\.[\w.]+|\w+)\s*\.\s*\w+(?:Anchor|Guide)[\w.]*\s*'
    r'(?:constraintEqualToAnchor|constraintGreaterThanOrEqualToAnchor|'
    r'constraintLessThanOrEqualToAnchor)\s*:\s*'
    r'(self\.[\w.]+|\w+)\s*\.\s*\w+(?:Anchor|Guide)[\w.]*\s*')


def strip_guide(name: str) -> str:
    for g in ('.safeAreaLayoutGuide', '.layoutMarginsGuide',
              '.readableContentGuide'):
        name = name.replace(g, '')
    return name


def audit_file(path: str):
    src = open(path, encoding='utf-8', errors='ignore').read()
    name = os.path.basename(path)

    parents = {}
    tracked = set()
    for m in ADD_RE.finditer(src):
        parent, child = m.group(1), m.group(2)
        parents[child] = parent
        tracked.add(parent)
        tracked.add(child)

    # 别名：self.footer = footer → 两者等价
    alias = {}
    for m in ALIAS_RE.finditer(src):
        prop, var = 'self.' + m.group(1), m.group(2)
        if var in tracked:
            alias[prop] = var
            alias[var] = prop
            tracked.add(prop)
            if var in parents:
                parents[prop] = parents[var]

    def tops(v):
        """自底向上收集祖先链"""
        chain, seen = [], set()
        while v and v not in seen:
            seen.add(v)
            chain.append(v)
            v = parents.get(v)
        return chain

    problems = []
    for m in CONSTRAINT_RE.finditer(src):
        a = strip_guide(m.group(1))
        b = strip_guide(m.group(2))
        if a == b:
            continue
        # 两边都必须被追踪到，否则无法判断
        if a not in tracked or b not in tracked:
            continue
        # 别名等价
        if alias.get(a) == b or alias.get(b) == a:
            continue
        if set(tops(a)) & set(tops(b)):
            continue

        line = src[:m.start()].count('\n') + 1
        problems.append(
            f'{name}:{line}: 跨树约束 {a} ↔ {b}\n'
            f'              {a} 祖先链: {tops(a)}\n'
            f'              {b} 祖先链: {tops(b)}')
    return problems


def main() -> int:
    root = sys.argv[1] if len(sys.argv) > 1 else 'Native/ObjC'
    files = sorted(glob.glob(os.path.join(root, '*.m')))
    if not files:
        print(f'[!] {root} 下没有 .m 文件')
        return 0

    all_problems = []
    for f in files:
        all_problems.extend(audit_file(f))

    if all_problems:
        print(f'[✗] {len(all_problems)} 处跨树约束：')
        for p in all_problems:
            print('    ' + p)
        return 1

    print(f'[ok] 约束层级审计通过（{len(files)} 个文件）')
    return 0


if __name__ == '__main__':
    sys.exit(main())
