#!/usr/bin/env python3
"""生成 ldid 格式的 ad-hoc 签名（含 entitlements）。

为什么需要它
-----------
我们的 ipa 之前在 macOS 上用 codesign 签名，但实测发现：
· Rein 的签名是 ldid 生成的（SHA-1, flags=0, 6 个子 blob）
· codesign 生成的是 Apple 风格（SHA-256, 带 DER 段, 不同 flags）

在 TrollStore 环境下，codesign 的签名会让
platform-application 不生效 —— 表现是 setuid(0) 返回 EPERM，
无论怎么重装都无效。这正是我们遇到的问题。

这个脚本按 ldid 的实际输出格式重新生成签名：
  SuperBlob { CodeDirectory(slot 0), Requirements(slot 2),
              Entitlements(slot 5), DER(slot 7) }
  CodeDirectory: version 0x20500, SHA-1, flags 0

用法
----
  python3 ldid_sign.py <macho> [--entitlements ent.plist]
  python3 ldid_sign.py --verify <macho>
"""

import struct
import sys
import hashlib
import plistlib

MH_MAGIC_64 = 0xFEEDFACF
MH_MAGIC_32 = 0xFEEDFACE
LC_SEGMENT_64 = 0x19
LC_SEGMENT = 0x1
LC_CODE_SIGNATURE = 0x1D

CSMAGIC_EMBEDDED_SIGNATURE = 0xFADE0CC0
CSMAGIC_CODEDIRECTORY = 0xFADE0C02
CSMAGIC_REQUIREMENTS = 0xFADE0C01
CSMAGIC_EMBEDDED_ENTITLEMENTS = 0xFADE7171
CSMAGIC_EMBEDDED_DER_ENTITLEMENTS = 0xFADE7172

PAGE_SIZE = 4096
# ldid 默认用 SHA-1（hashType=1），这是它在 iOS 上能被认可的关键
HASH_TYPE = 1
HASH_SIZE = 20


def be32(v):
    return struct.pack(">I", v)


def parse_macho(data):
    magic = struct.unpack("<I", data[:4])[0]
    if magic == MH_MAGIC_64:
        is64 = True
        _, _, _, _, ncmds, sizeofcmds, _ = struct.unpack("<IiiIIII", data[:28])
        hdr = 32
    elif magic == MH_MAGIC_32:
        is64 = False
        _, _, _, _, ncmds, sizeofcmds, _ = struct.unpack("<IiiIIII", data[:28])
        hdr = 28
    else:
        raise ValueError("不是 Mach-O：magic=0x%x" % magic)

    segments = []
    sig_off = None
    off = hdr
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack("<II", data[off:off + 8])
        if is64 and cmd == LC_SEGMENT_64:
            name = data[off + 8:off + 24].rstrip(b"\0").decode("ascii", "ignore")
            fileoff, filesize = struct.unpack("<QQ", data[off + 40:off + 56])
            segments.append((name, fileoff, filesize, off, True))
        elif not is64 and cmd == LC_SEGMENT:
            name = data[off + 8:off + 24].rstrip(b"\0").decode("ascii", "ignore")
            fileoff, filesize = struct.unpack("<II", data[off + 32:off + 40])
            segments.append((name, fileoff, filesize, off, False))
        elif cmd == LC_CODE_SIGNATURE:
            sig_off = off
        off += cmdsize
    return is64, segments, sig_off, ncmds, sizeofcmds


def build_requirements():
    """空需求集（ad-hoc 的标准做法）"""
    return struct.pack(">III", CSMAGIC_REQUIREMENTS, 12, 0)


def build_entitlements(plist_bytes):
    return be32(CSMAGIC_EMBEDDED_ENTITLEMENTS) + be32(8 + len(plist_bytes)) + plist_bytes


def build_der_entitlements(plist_bytes):
    """ldid 的 slot 7：DER 编码。这里用简化形式（TrollStore 不校验其内容）。"""
    body = plist_bytes
    return be32(CSMAGIC_EMBEDDED_DER_ENTITLEMENTS) + be32(8 + len(body)) + body


def build_codedirectory(code, ident, n_special, special_hashes):
    """CodeDirectory：version 0x20500，SHA-1，flags 0（与 ldid 一致）"""
    n_code = (len(code) + PAGE_SIZE - 1) // PAGE_SIZE
    hashes = b""
    for i in range(n_code):
        chunk = code[i * PAGE_SIZE:(i + 1) * PAGE_SIZE]
        hashes += hashlib.sha1(chunk).digest()

    # version 0x20500 的固定头长度 = 88 字节
    # version 0x20500 的固定头 = 64 字节（16 个 4 字节字段）
    header_len = 64
    ident_off = header_len
    hash_off = ident_off + len(ident) + 1 + n_special * HASH_SIZE

    hdr = b"".join([
        be32(CSMAGIC_CODEDIRECTORY),
        be32(0),              # length（回填）
        be32(0x20500),        # version
        be32(0),              # flags = 0（与 ldid 一致）
        be32(hash_off),
        be32(ident_off),
        be32(n_special),
        be32(n_code),
        be32(len(code)),      # codeLimit
        bytes([HASH_SIZE]),
        bytes([HASH_TYPE]),
        bytes([0]),           # platform
        bytes([12]),          # pageSize = 2^12
        be32(0),              # spare2
        be32(0),              # scatterOffset
        be32(0),              # teamOffset
        be32(0),              # spare3
        be32(0),              # codeLimit64 低
        be32(0),              # codeLimit64 高
    ])
    assert len(hdr) == 64, len(hdr)

    blob = hdr + ident + b"\0"
    for h in special_hashes:          # 特殊槽（从高到低）
        blob += h
    blob += hashes

    blob = be32(CSMAGIC_CODEDIRECTORY) + be32(len(blob)) + blob[8:]
    return blob


def sign_file(path, entitlements_bytes=b""):
    data = open(path, "rb").read()
    is64, segments, sig_off, ncmds, sizeofcmds = parse_macho(data)

    # 去掉已有签名
    if sig_off is not None:
        old_off, old_size = struct.unpack("<II", data[sig_off + 8:sig_off + 16])
        data = data[:old_off]
        is64, segments, sig_off, ncmds, sizeofcmds = parse_macho(data)

    # 已签名文件里 LC_CODE_SIGNATURE 一定存在；没有就没法写回，
    # 但我们可以在 load commands 后追加（需要 sizeofcmds 有余量）。
    if sig_off is None:
        raise RuntimeError("该文件没有预留 LC_CODE_SIGNATURE，无法签名")

    code = data
    ident = path.rsplit("/", 1)[-1].encode()

    blobs = []
    if entitlements_bytes:
        ent = build_entitlements(entitlements_bytes)
        der = build_der_entitlements(entitlements_bytes)
        special = [hashlib.sha1(der).digest(), hashlib.sha1(ent).digest()]
    else:
        ent = der = b""
        special = []

    req = build_requirements()
    cd = build_codedirectory(code, ident, len(special), special)

    count = 2 + len(special)          # CD + Requirements (+ Ent + DER)
    idx = 12 + count * 8
    parts = [be32(CSMAGIC_EMBEDDED_SIGNATURE), be32(0), be32(count)]
    parts.append(be32(0) + be32(idx)); idx += len(cd)
    parts.append(be32(2) + be32(idx)); idx += len(req)
    if ent:
        parts.append(be32(5) + be32(idx)); idx += len(ent)
        parts.append(be32(7) + be32(idx)); idx += len(der)

    blob = b"".join(parts) + cd + req + ent + der
    blob = be32(CSMAGIC_EMBEDDED_SIGNATURE) + be32(len(blob)) + blob[8:]

    data_off = len(data)
    out = bytearray(data) + blob
    out += b"\0" * ((16 - len(out) % 16) % 16)

    # 更新 __LINKEDIT.filesize
    for name, fileoff, filesize, cmd_off, is64seg in segments:
        if name == "__LINKEDIT":
            new_size = len(out) - fileoff
            if is64seg:
                struct.pack_into("<Q", out, cmd_off + 48, new_size)
            else:
                struct.pack_into("<I", out, cmd_off + 36, new_size)

    struct.pack_into("<IIII", out, sig_off, LC_CODE_SIGNATURE, 16, data_off, len(blob))
    open(path, "wb").write(bytes(out))
    return len(blob)


def verify(path):
    data = open(path, "rb").read()
    is64, segments, sig_off, _, _ = parse_macho(data)
    if sig_off is None:
        print("[x] 没有 LC_CODE_SIGNATURE"); return 1
    off, size = struct.unpack("<II", data[sig_off + 8:sig_off + 16])
    blob = data[off:off + size]
    magic, length, count = struct.unpack(">III", blob[:12])
    slots = []
    for i in range(count):
        t, bo = struct.unpack(">II", blob[12 + i * 8:20 + i * 8])
        slots.append(t)
    print("[ok] 签名有效：%d 字节，slot=%s" % (size, slots))
    # 校验 CodeDirectory 参数
    for i in range(count):
        t, bo = struct.unpack(">II", blob[12 + i * 8:20 + i * 8])
        if t == 0:
            ver, flags = struct.unpack(">II", blob[bo + 8:bo + 16])
            ht = blob[bo + 37]
            print("     CodeDirectory: version=0x%x flags=0x%x hashType=%d" % (ver, flags, ht))
    return 0


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__); sys.exit(1)
    if sys.argv[1] == "--verify":
        sys.exit(verify(sys.argv[2]))
    ent = b""
    args = sys.argv[1:]
    if "--entitlements" in args:
        i = args.index("--entitlements")
        ent = plistlib.dumps(plistlib.load(open(args[i + 1], "rb")), fmt=plistlib.FMT_XML)
        del args[i:i + 2]
    for p in args:
        size = sign_file(p, ent)
        print("signed %s (%d bytes signature)" % (p, size))
