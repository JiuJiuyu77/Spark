#!/usr/bin/env python3
"""校验 entitlements.plist —— 按「Helper 必需 / 可选 / 绝对不要」清单。

这份清单来自实际踩坑总结：

必须（Helper 能起来的前提）
  com.apple.private.security.storage-exempt.heritable   make/clang/ldid 子进程继承豁免，最关键
  com.apple.private.persona-mgmt                         以 root 身份 spawn
  com.apple.private.security.storage.AppBundles          读别的 App bundle
  com.apple.private.MobileContainerManager.allowed       查容器
  com.apple.private.amfi.developer-mode-control          iOS 16+ 开发者模式
  platform-application                                   平台身份
  com.apple.private.security.no-sandbox                  脱离沙盒

可选
  com.apple.private.mobileinstall.allowedSPI             Helper 参与安装产物时才需要

绝对不要（A12+/iOS 15+ 加了直接崩，Helper 起不来）
  dynamic-codesigning
  com.apple.private.cs.debugger
  com.apple.private.skip-library-validation

用法
----
    python3 scripts/check-entitlements.py [entitlements.plist]
"""

import plistlib
import sys

# 必须是 true 的项
# 必需项只保留「提权 + 脱沙盒」的最小集合。
# 依据：对照 Rein（DSH.app）实际写入二进制的 13 项，
# MobileContainerManager.allowed / amfi.developer-mode-control /
# task_for_pid-allow 这三项它都没有，却依然能拿到 root ——
# 说明它们不是提权必要条件，写多了反而可能引起降权。
REQUIRED_TRUE = [
    'com.apple.private.security.storage-exempt.heritable',
    'com.apple.private.persona-mgmt',
    'com.apple.private.security.storage.AppBundles',
    'platform-application',
    'com.apple.private.security.no-sandbox',
]

# 可选（有则更好，没有不影响提权）——仅提示，不报错
OPTIONAL_TRUE = [
    'com.apple.private.MobileContainerManager.allowed',
    'com.apple.private.amfi.developer-mode-control',
    'task_for_pid-allow',
    'com.apple.private.security.storage.AppDataContainers',
    'proc_info-allow',
    'com.apple.developer.kernel.extended-virtual-addressing',
]

# 必须是 false 的项
REQUIRED_FALSE = [
    'com.apple.private.security.container-required',
]

# 必须存在且非空（数组）
# 有 no-sandbox 时本项非必需（Rein 就没有这一项）。
# 保留为空列表也没问题，仅在需要访问沙盒外特定路径时才用。
REQUIRED_NONEMPTY_LIST = []

# 绝对不要出现（A12+/iOS 15+ 会崩）
PROHIBITED = [
    'dynamic-codesigning',
    'com.apple.private.cs.debugger',
    'com.apple.private.skip-library-validation',
]

# 可选，仅作提示
OPTIONAL = [
    'com.apple.private.mobileinstall.allowedSPI',
]


def main() -> int:
    path = sys.argv[1] if len(sys.argv) > 1 else 'entitlements.plist'
    try:
        with open(path, 'rb') as f:
            d = plistlib.load(f)
    except Exception as e:
        print(f'[✗] 读不了 {path}: {e}')
        return 1

    problems = []

    for k in REQUIRED_TRUE:
        if d.get(k) is not True:
            problems.append(f'必须为 true：{k}（当前 {d.get(k)!r}）')

    for k in REQUIRED_FALSE:
        if d.get(k) is not False:
            problems.append(f'必须为 false：{k}（当前 {d.get(k)!r}）')

    for k in REQUIRED_NONEMPTY_LIST:
        v = d.get(k)
        if not isinstance(v, list) or not v:
            problems.append(f'必须是非空数组：{k}（当前 {v!r}）')

    for k in PROHIBITED:
        if k in d:
            problems.append(f'绝对不能有：{k}（A12+/iOS 15+ 会导致 Helper 崩溃）')

    if problems:
        print(f'[✗] entitlements 有 {len(problems)} 处问题：')
        for p in problems:
            print('    - ' + p)
        return 1

    print(f'[ok] entitlements 校验通过（{len(d)} 项）')
    missing_optional = [k for k in OPTIONAL if k not in d]
    if missing_optional:
        print(f'     可选未开启：{", ".join(missing_optional)}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
