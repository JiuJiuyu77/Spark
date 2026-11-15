#!/usr/bin/env python3
"""校验目录下每个 Mach-O 都有 LC_CODE_SIGNATURE。

为什么需要
----------
TrollStore 安装 ipa 时执行：

    ldid -s Payload/Spark.app

它会递归遍历 .app，对每个 Mach-O 重新签名。
遇到**没有签名段的 Mach-O**（例如我们用 clang 直接编出来、
还没 codesign 过的 helper），ldid 处理会失败，
最终报 "ldid: Unknown header magic"，安装返回 175（实测踩坑）。

这个脚本在打包前把关：任何 Mach-O 缺签名就直接失败。

用法
----
    python3 scripts/check-macho-signed.py <目录>

退出码
------
0 = 全部已签名
1 = 存在未签名的 Mach-O
"""

import os
import struct
import sys

MACHO_MAGIC = {
    b'\xcf\xfa\xed\xfe',  # MH_MAGIC_64 (little)
    b'\xce\xfa\xed\xfe',  # MH_MAGIC    (little)
    b'\xfe\xed\xfa\xcf',  # MH_MAGIC_64 (big)
    b'\xfe\xed\xfa\xce',  # MH_MAGIC    (big)
}

LC_CODE_SIGNATURE = 0x1d


def has_code_signature(path: str) -> bool:
    with open(path, 'rb') as f:
        head = f.read(32)
        if len(head) < 32:
            return False
        ncmds = struct.unpack('<I', head[16:20])[0]
        off = 32
        for _ in range(ncmds):
            f.seek(off)
            raw = f.read(8)
            if len(raw) < 8:
                break
            cmd, size = struct.unpack('<II', raw)
            if cmd == LC_CODE_SIGNATURE:
                return True
            if size < 8:
                break
            off += size
    return False


def main() -> int:
    root = sys.argv[1] if len(sys.argv) > 1 else '.'
    if not os.path.isdir(root):
        print(f'[✗] 目录不存在: {root}')
        return 1

    macho = 0
    unsigned = []
    for base, _dirs, files in os.walk(root):
        for fn in files:
            p = os.path.join(base, fn)
            try:
                with open(p, 'rb') as f:
                    magic = f.read(4)
            except OSError:
                continue
            if magic not in MACHO_MAGIC:
                continue
            macho += 1
            try:
                if not has_code_signature(p):
                    unsigned.append(os.path.relpath(p, root))
            except OSError:
                unsigned.append(os.path.relpath(p, root) + '（读取失败）')

    if unsigned:
        print(f'[✗] {len(unsigned)}/{macho} 个 Mach-O 未签名，ldid -s 会失败：')
        for u in unsigned:
            print('    - ' + u)
        return 1

    print(f'[ok] 全部 {macho} 个 Mach-O 均已签名')
    return 0


if __name__ == '__main__':
    sys.exit(main())
