#!/usr/bin/env python3
"""检查 ObjC 代码里的常见质量隐患。

检查项
------
1. **永久等待**：`dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER)`
   一旦回调没被触发，调用线程（可能是主线程）会永久卡死。

2. **block 强引用 self**：
   `self.block = ^{ ... self.xxx ... }` 或
   `[obj method:^{ ... self ... }]` 中直接用 self 且没有 weak/strong 桥接，
   容易造成循环引用（self → block → self）。

3. **主线程同步等待**：在 viewDidLoad / 按钮回调里直接
   `dispatch_semaphore_wait`，会卡 UI。

4. **error:NULL 吞掉错误**：`... error:NULL` 用于可能失败的关键操作时
   无法排查。只统计，不报错（数量太多时人工看）。

用法
----
    python3 scripts/check-quality.py [目录]
"""

import glob
import os
import re
import sys

# 允许的白名单（已知安全）
ALLOW_FOREVER_WAIT = {
    # 明确的阻塞式 API，本身就在后台线程调用
}

MAIN_THREAD_ENTRY = (
    'viewDidLoad', 'viewWillAppear', 'viewDidAppear',
    'didSelectRowAtIndexPath', 'cellForRowAtIndexPath',
    'tableView:', 'collectionView:', 'viewDidLayoutSubviews',
)


def strip_comments(text: str) -> str:
    text = re.sub(r'//[^\n]*', '', text)
    text = re.sub(r'/\*[\s\S]*?\*/', '', text)
    return text


def check_file(path: str):
    raw = open(path, encoding='utf-8', errors='ignore').read()
    text = strip_comments(raw)
    name = os.path.basename(path)
    lines = text.split('\n')
    problems = []
    notes = []

    for i, line in enumerate(lines, 1):
        # 1. 永久等待
        if 'DISPATCH_TIME_FOREVER' in line and 'dispatch_semaphore_wait' in line:
            problems.append(
                f'{name}:{i}: dispatch_semaphore_wait 用了 DISPATCH_TIME_FOREVER，'
                f'回调未触发时会永久卡死。改用带超时的等待。')

        # 3. 主线程入口里的同步等待
        if 'dispatch_semaphore_wait' in line:
            # 往上找最近的方法签名
            for j in range(i - 1, max(0, i - 40), -1):
                m = re.match(r'\s*[-+]\s*\(([^)]*)\)\s*(\w+)', lines[j])
                if m:
                    sel = m.group(2)
                    if any(k in lines[j] for k in MAIN_THREAD_ENTRY):
                        problems.append(
                            f'{name}:{i}: 在 UI 回调（{sel}）里同步等待信号量，会卡住界面。'
                            f'改为异步 + 回调。')
                    break

    # 2. block 强引用 self —— 只报「会被存储」的 block
    #
    # 关键区分：
    #   · 动画/一次性的 block（UIView animate / SPMotion / dispatch_after）
    #     执行完就释放，不会形成环 —— 不报
    #   · 会被对象长期持有的 block（赋值给属性、传给会保存它的方法）
    #     才是真正的循环引用风险 —— 报
    ANIMATION_CALLS = ('animate', 'spring', 'appear', 'fade', 'pulse',
                       'dispatch_after', 'performBatchUpdates', 'addAnimations',
                       'stagger', 'ripple', 'breathe')
    STORED_HINTS = ('onFinish', 'onLine', 'onTap', 'onSave', 'onPick',
                    'onOpenFile', 'onProjectUpdated', 'completionHandler)',
                    'handler =', 'block =', 'callback =')

    for i, line in enumerate(lines, 1):
        if not re.search(r'\^\s*\{.*\bself\b.*\}', line):
            continue
        if 'weakSelf' in line or 'typeof(self)' in line:
            continue
        # 动画类 block：跳过
        if any(c in line for c in ANIMATION_CALLS):
            continue
        # 只报看起来会被存储的
        if any(h in line for h in STORED_HINTS):
            problems.append(
                f'{name}:{i}: 会被保存的 block 里直接引用 self，可能循环引用。'
                f'建议 __weak typeof(self) weakSelf = self;')

    # 4. 统计
    n_null = text.count('error:NULL')
    if n_null:
        notes.append(f'{name}: error:NULL ×{n_null}')

    return problems, notes


def main() -> int:
    root = sys.argv[1] if len(sys.argv) > 1 else 'Native/ObjC'
    files = sorted(glob.glob(os.path.join(root, '*.m')))
    if not files:
        print(f'[!] {root} 下没有 .m 文件')
        return 0

    all_problems = []
    all_notes = []
    for f in files:
        p, n = check_file(f)
        all_problems.extend(p)
        all_notes.extend(n)

    # 已知例外：SPSession 的 runSyncShell 是同步 API，调用方保证在后台线程
    all_problems = [p for p in all_problems
                    if not (p.startswith('SPSession.m') and 'DISPATCH_TIME_FOREVER' in p)]

    if all_problems:
        print(f'[✗] {len(all_problems)} 处质量隐患：')
        for p in all_problems:
            print('    ' + p)
        return 1

    print(f'[ok] 质量检查通过（{len(files)} 个文件）')
    if all_notes:
        total = sum(int(n.split('×')[1]) for n in all_notes)
        print(f'     提示：error:NULL 共 {total} 处（多为可选参数，可接受）')
    return 0


if __name__ == '__main__':
    sys.exit(main())
