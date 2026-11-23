#!/usr/bin/env python3
"""校验目录下每个 Mach-O 完好且已签名。

为什么需要
----------
TrollStore 安装时执行 `ldid -s Payload/Workbench.app`，它逐个处理 Mach-O。
两种损坏都会导致安装失败：

1. **未签名**（没有 LC_CODE_SIGNATURE）
   裸 clang 编出来的 helper 就是这种情况。

2. **文件被截断**（LC_CODE_SIGNATURE 的 dataoff 超出文件实际大小）
   典型场景：下载/解包的 tar.gz 不完整，108MB 的 libLLVM 只剩 49MB。
   ldid 会报：
       ldid.cpp(1554): _assert(): size <= mach_header.GetSize()

这两种在本项目都真实发生过，所以必须都查。

用法
----
    python3 scripts/check-macho.py <目录>

退出码
------
0 = 全部完好且已签名
1 = 存在未签名或损坏的 Mach-O
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

LC_CODE_SIGNATURE = 0x1D
LC_SYMTAB = 0x02

# libLLVM 这类大文件如果小于这个值，基本可以断定是截断
MIN_SANE_LLVM_BYTES = 100 * 1024 * 1024


def inspect(path: str):
    """返回 (状态, 说明)。状态: ok / unsigned / truncated / bad"""
    size = os.path.getsize(path)
    with open(path, 'rb') as f:
        head = f.read(32)
        if len(head) < 32:
            return 'bad', '文件过小'

        ncmds = struct.unpack('<I', head[16:20])[0]

        off = 32
        sig_dataoff = None
        end_of_cmds = 32
        for _ in range(ncmds):
            if off + 8 > size:
                return 'bad', 'load command 越界'
            f.seek(off)
            raw = f.read(8)
            if len(raw) < 8:
                return 'bad', 'load command 读取失败'
            cmd, cmdsize = struct.unpack('<II', raw)
            if cmdsize < 8:
                return 'bad', 'load command 尺寸异常'
            if cmd == LC_CODE_SIGNATURE and off + 16 <= size:
                f.seek(off + 8)
                sig_dataoff = struct.unpack('<I', f.read(4))[0]
            off += cmdsize
            end_of_cmds = off

    if sig_dataoff is None:
        return 'unsigned', '缺少 LC_CODE_SIGNATURE'

    # 关键检查：签名数据偏移不能超出文件实际大小
    if sig_dataoff > size:
        return 'truncated', (
            f'签名偏移 {sig_dataoff} > 文件大小 {size}'
            f'（差 {sig_dataoff - size} 字节，文件被截断）')

    if sig_dataoff < end_of_cmds:
        return 'bad', f'签名偏移 {sig_dataoff} 小于命令区结束位置 {end_of_cmds}'

    return 'ok', ''


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    # --no-signature：只检查完好性（截断/头部损坏），不要求已签名。
    # 签名前用这个：此时主程序还没签名是正常的。
    allow_unsigned = '--no-signature' in sys.argv[1:]
    root = args[0] if args else '.'
    if not os.path.isdir(root):
        print(f'[✗] 目录不存在: {root}')
        return 1

    total = 0
    problems = []

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
            total += 1
            state, why = inspect(p)
            if state == 'unsigned' and allow_unsigned:
                continue
            if state != 'ok':
                problems.append((os.path.relpath(p, root), state, why))

            # 额外检查：libLLVM 这类大文件不能明显偏小
            if 'libLLVM' in fn and os.path.getsize(p) < MIN_SANE_LLVM_BYTES:
                problems.append((
                    os.path.relpath(p, root), 'truncated',
                    f'仅 {os.path.getsize(p) // 1048576} MB，应约 108 MB'))

    if problems:
        print(f'[✗] {len(problems)} 个 Mach-O 有问题（共 {total} 个），ldid -s 会失败：')
        for rel, state, why in problems:
            print(f'    [{state}] {rel}')
            print(f'              {why}')
        return 1

    print(f'[ok] 全部 {total} 个 Mach-O 完好且已签名')
    return 0


if __name__ == '__main__':
    sys.exit(main())
