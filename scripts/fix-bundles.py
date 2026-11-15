#!/usr/bin/env python3
"""清理「空壳 bundle」——防止 TrollStore 的 ldid -s 安装失败。

问题背景
--------
TrollStore 安装 ipa 的最后一步是：

    ldid -s Payload/Spark.app

ldid 的目录签名逻辑（见 ldid.cpp 的 Sign(root, folder, ...)）：
  1. 递归找 `Frameworks/*.framework/Info.plist` 与
     `PlugIns/*.appex/Info.plist`
  2. 对每个 bundle 读 Info.plist 的 CFBundleExecutable
  3. 打开 <bundle>/<CFBundleExecutable>

Theos 的 vendor 目录里很多 framework 只带 `.tbd` 桩文件（供编译链接），
没有真实二进制。Step 3 打开失败 → 读到空内容 → ldid 报

    ldid: Unknown header magic

整个安装返回 175，用户完全装不上。

这个脚本做的事
--------------
扫描 .app 下所有 Info.plist，凡是 CFBundleExecutable 指向的文件不存在，
就删掉这个 Info.plist。

为什么删 Info.plist 是安全的
----------------------------
· 这些 bundle 在编译时只用到 `.tbd` 与 `Headers/`，不读 Info.plist
· App 自身与 Share Extension 的 Info.plist 会保留（它们的可执行文件存在）
· 纯模板目录（vendor/templates/**/Resources/Info.plist）也只是占位

用法
----
    python3 scripts/fix-bundles.py <Payload/Spark.app 的路径>

退出码
------
0 = 成功（无论是否有移除）
1 = 参数错误
"""

import os
import plistlib
import sys


def fix_root(root: str) -> int:
    removed = []
    scanned = 0

    for base, _dirs, files in os.walk(root):
        if 'Info.plist' not in files:
            continue
        ip = os.path.join(base, 'Info.plist')
        scanned += 1

        try:
            with open(ip, 'rb') as f:
                data = plistlib.load(f)
        except Exception:
            # 读不了的 Info.plist 不动它（可能是二进制/加密的，另有用途）
            continue

        if not isinstance(data, dict):
            continue

        exe = data.get('CFBundleExecutable')
        if not exe:
            # 没有 CFBundleExecutable 的 Info.plist，ldid 不会递归进去
            continue

        target = os.path.join(base, exe)
        if os.path.exists(target):
            continue

        rel = os.path.relpath(ip, root)
        # Theos 分发包里文件普遍是只读（444），删之前先加写权限
        try:
            os.chmod(ip, 0o644)
        except OSError:
            pass
        try:
            os.remove(ip)
            removed.append(rel)
        except OSError as e:
            # 目录只读也会导致删除失败，连父目录一起放开
            try:
                os.chmod(base, 0o755)
                os.remove(ip)
                removed.append(rel)
            except OSError as e2:
                print(f'  [!] 删除失败 {rel}: {e2}', file=sys.stderr)

    print(f'  扫描 Info.plist {scanned} 个，移除空壳 {len(removed)} 个')
    for r in removed:
        print(f'    - {r}')
    return 0


def check_root(root: str) -> int:
    """只探测不修改：返回空壳 bundle 数量（用于签名前硬校验）。"""
    bad = []
    for base, _dirs, files in os.walk(root):
        if 'Info.plist' not in files:
            continue
        ip = os.path.join(base, 'Info.plist')
        try:
            with open(ip, 'rb') as f:
                d = plistlib.load(f)
        except Exception:
            continue
        if not isinstance(d, dict):
            continue
        exe = d.get('CFBundleExecutable')
        if exe and not os.path.exists(os.path.join(base, exe)):
            bad.append(os.path.relpath(ip, root))

    if bad:
        print('::error::仍有 %d 个空壳 bundle，ldid -s 会失败' % len(bad))
        for b in bad:
            print('    ' + b)
        return 1
    print('  ✓ 无空壳 bundle')
    return 0


def main() -> int:
    args = [a for a in sys.argv[1:] if a != '--check']
    check_only = '--check' in sys.argv[1:]

    if not args:
        print('用法: fix-bundles.py [--check] <Payload/Spark.app>', file=sys.stderr)
        return 1
    root = args[0]
    if not os.path.isdir(root):
        print(f'目录不存在: {root}', file=sys.stderr)
        return 1
    return check_root(root) if check_only else fix_root(root)


if __name__ == '__main__':
    sys.exit(main())
