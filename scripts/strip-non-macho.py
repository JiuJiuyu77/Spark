#!/usr/bin/env python3
"""把「ldid 无法处理的二进制」移出 .app。

问题
----
TrollStore 安装 ipa 时执行 `ldid -s Payload/Workbench.app`。
ldid 会遍历 .app 下每个普通文件，按 magic 判断是否 Mach-O：

    ldid.cpp  Sign() → folder.Find() → 对每个文件读前 16 字节

认得的 magic：
    MH_MAGIC / MH_MAGIC_64 / MH_CIGAM / MH_CIGAM_64     普通 Mach-O
    FAT_MAGIC / FAT_CIGAM                                通用二进制
    FAT_MAGIC + count < 40                               兼容 Java class

遇到其它内容 → "ldid: Unknown header magic" → 安装返回 175。

本项目踩过的坑（真实案例）
--------------------------
`theos/vendor/lib/libroot*.a` 是 **FAT 通用二进制，但里面装的是 ar 静态库**：

    $ file libroot.a
    Mach-O universal binary with 5 architectures:
      [armv6: current ar archive] [armv7: ...] [arm64: ...]

ldid 看到 FAT_MAGIC 认为可以处理，进去取第一个切片，
发现是 `!<arch>` 归档 → 不是 Mach-O → Unknown header magic。

检测逻辑
--------
对每个文件：
  1. magic 是 MH_*  → 正常 Mach-O，保留
  2. magic 是 FAT   → 进去看第一个切片的 magic
                       是 MH_*  → 保留（真正的 universal binary）
                       是 !<arch> → 移走（FAT 包 ar，ldid 处理不了）
  3. magic 是 !<arch> → 移走（纯 ar 静态库）
  4. 其它且扩展名 .a → 移走

被移走的文件放到 `<App>.app.toolchain-extra/`，不进入 ipa。
移走而不是删除，方便事后排查。

用法
----
    python3 scripts/strip-non-macho.py <Payload/Workbench.app>
"""

import os
import shutil
import struct
import sys

MH_MAGIC = {
    0xFEEDFACE, 0xFEEDFACF, 0xCEFAEDFE, 0xCFFAEDFE,
}
FAT_MAGIC = {
    0xCAFEBABE, 0xCAFEBABF, 0xBEBAFECA, 0xBFBAFECA,
}
AR_MAGIC = b'!<arch>\n'


def read_u32(b: bytes) -> int:
    return struct.unpack('>I', b[:4])[0]


def classify(path: str):
    """返回 (是否移走, 说明)"""
    try:
        with open(path, 'rb') as f:
            head = f.read(4096)
    except OSError:
        return False, ''

    if len(head) < 8:
        return False, ''

    # 纯 ar 静态库
    if head[:8] == AR_MAGIC:
        return True, 'ar 静态库'

    magic = read_u32(head[:4])

    # 普通 Mach-O
    if magic in MH_MAGIC:
        return False, ''

    # FAT 通用二进制：检查第一个切片
    if magic in FAT_MAGIC:
        # fat_header: magic(4) nfat_arch(4)，后面是 fat_arch 数组
        # fat_arch: cputype(4) cpusubtype(4) offset(4) size(4) align(4)
        if len(head) >= 8 + 20:
            first_off = struct.unpack('>I', head[8 + 8: 8 + 12])[0]
            try:
                with open(path, 'rb') as f:
                    f.seek(first_off)
                    sub = f.read(8)
                if sub[:8] == AR_MAGIC or sub[:4] == b'!<ar':
                    return True, 'FAT 通用二进制，内含 ar 静态库（ldid 处理不了）'
                if read_u32(sub[:4]) in MH_MAGIC:
                    return False, ''      # 真正的 universal binary
            except OSError:
                return True, 'FAT 切片读取失败'
        return True, 'FAT 通用二进制结构异常'

    # 兜底：扩展名 .a
    if path.endswith('.a'):
        return True, '静态库（扩展名判定）'

    return False, ''


def check_only(app: str) -> int:
    """只探测不移动：有 ldid 处理不了的二进制就返回 1。"""
    bad = []
    for base, _dirs, files in os.walk(app):
        for fn in files:
            p = os.path.join(base, fn)
            need, why = classify(p)
            if need:
                bad.append((os.path.relpath(p, app), why))
    if bad:
        print(f'[✗] {len(bad)} 个 ldid 处理不了的二进制，安装会失败：')
        for rel, why in bad:
            print(f'    - {rel}  （{why}）')
        return 1
    print('  ✓ 无 ldid 处理不了的二进制')
    return 0


def main() -> int:
    if len(sys.argv) < 2:
        print('用法: strip-non-macho.py <Payload/Workbench.app>', file=sys.stderr)
        return 1

    # 支持 --check 放在任意位置
    positional = [a for a in sys.argv[1:] if not a.startswith('--')]
    if not positional:
        print('用法: strip-non-macho.py [--check] <Payload/Workbench.app>', file=sys.stderr)
        return 1

    app = positional[0]
    if not os.path.isdir(app):
        print(f'[✗] 目录不存在: {app}', file=sys.stderr)
        return 1

    if '--check' in sys.argv[1:]:
        return check_only(app)

    outdir = app.rstrip('/') + '.toolchain-extra'
    moved = []

    for base, _dirs, files in os.walk(app):
        for fn in files:
            p = os.path.join(base, fn)
            need, why = classify(p)
            if not need:
                continue

            rel = os.path.relpath(p, app)
            for target, mode in ((os.path.dirname(p), 0o755), (p, 0o644)):
                try:
                    os.chmod(target, mode)
                except OSError:
                    pass

            dest = os.path.join(outdir, rel)
            try:
                os.makedirs(os.path.dirname(dest), exist_ok=True)
                shutil.move(p, dest)
                moved.append((rel, why))
            except OSError as e:
                print(f'  [!] 移动失败 {rel}: {e}', file=sys.stderr)

    if moved:
        print(f'  移出 {len(moved)} 个 ldid 处理不了的二进制：')
        for rel, why in moved:
            print(f'    - {rel}')
            print(f'      {why}')
    else:
        print('  ✓ 无 ldid 处理不了的二进制')
    return 0


if __name__ == '__main__':
    sys.exit(main())
