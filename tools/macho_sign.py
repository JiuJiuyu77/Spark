#!/usr/bin/env python3
"""纯 Python 的 ad-hoc 签名工具（ldid 替代品）。

为什么需要
----------
ish 里没有 ldid，但 iOS 上的 dylib / 可执行文件必须带 LC_CODE_SIGNATURE
才能被加载（TrollStore 环境下是 ad-hoc 签名）。

实现思路（照 ldid 的 adhoc 做法）
--------------------------------
1. 解析 Mach-O，找到最后一个段（一般是 __LINKEDIT）
2. 在文件末尾追加 SuperBlob：
   CodeDirectory + Requirements(空) + Entitlements(可选)
3. CodeDirectory 里对「文件本身按 16KB 分页」逐页算 SHA-256
4. 更新 __LINKEDIT 的 filesize 与 LC_CODE_SIGNATURE 的 dataoff/datasize

这个实现只处理单架构 64 位 Mach-O（arm64），够 ish 的产物用。

用法
----
    python3 macho_sign.py <file>            # 签名
    python3 macho_sign.py --verify <file>   # 只校验已有签名
"""

import hashlib
import struct
import sys

MH_MAGIC_64 = 0xFEEDFACF
LC_SEGMENT_64 = 0x19
LC_CODE_SIGNATURE = 0x1D
CSMAGIC_EMBEDDED_SIGNATURE = 0xFADE0CC0
CSMAGIC_CODEDIRECTORY = 0xFADE0C02
CSMAGIC_REQUIREMENTS = 0xFADE0C01
CS_ADHOC = 0x00000002
PAGE_SIZE = 4096


def be32(v):
    return struct.pack(">I", v)


def parse_macho(data):
    """返回 (ncmds, sizeofcmds, segments, sig_cmd_offset)"""
    if len(data) < 32:
        raise ValueError("文件过小")
    magic, cputype, cpusub, filetype, ncmds, sizeofcmds, flags = struct.unpack(
        "<IiiIIII", data[:28]
    )
    if magic != MH_MAGIC_64:
        raise ValueError("只支持 64 位小端 Mach-O")
    segments = []
    sig_off = None
    off = 32
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack("<II", data[off:off + 8])
        if cmd == LC_SEGMENT_64:
            segname = data[off + 8:off + 24].rstrip(b"\0").decode("ascii", "ignore")
            vmaddr, vmsize, fileoff, filesize = struct.unpack(
                "<QQQQ", data[off + 24:off + 56]
            )
            segments.append(
                {"name": segname, "vmaddr": vmaddr, "vmsize": vmsize,
                 "fileoff": fileoff, "filesize": filesize, "cmd_off": off}
            )
        elif cmd == LC_CODE_SIGNATURE:
            sig_off = off
        off += cmdsize
    return filetype, segments, sig_off, ncmds


def build_entitlements_blob(xml: bytes) -> bytes:
    """构造 entitlements slot（slot 5）"""
    body = struct.pack(">II", 0xFADE7171, 8 + len(xml)) + xml
    return body


def build_requirements() -> bytes:
    """空需求集（ad-hoc 常用）"""
    return struct.pack(">III", CSMAGIC_REQUIREMENTS, 12, 0)


def build_codedirectory(code_bytes: bytes, ident: bytes, ent_offset: int = 0) -> bytes:
    """构造 CodeDirectory（version 0x20400，SHA-256）"""
    n_code = (len(code_bytes) + PAGE_SIZE - 1) // PAGE_SIZE
    hashes = b""
    for i in range(n_code):
        chunk = code_bytes[i * PAGE_SIZE:(i + 1) * PAGE_SIZE]
        hashes += hashlib.sha256(chunk).digest()

    # 固定头部字段长度（version 0x20400）：
    #  magic,length,version,flags,hashOffset,identOffset,nSpecialSlots,nCodeSlots,
    #  codeLimit,hashSize,hashType,platform,pageSize,spare2,scatterOffset,teamOffset
    header_len = 88
    ident_off = header_len
    hash_off = header_len + len(ident) + 1

    hdr = b"".join([
        be32(CSMAGIC_CODEDIRECTORY),
        be32(0),                      # length 稍后回填
        be32(0x20400),                # version
        be32(CS_ADHOC),               # flags
        be32(hash_off),               # hashOffset
        be32(ident_off),              # identOffset
        be32(1 if ent_offset else 0), # nSpecialSlots（slot 5 = entitlement）
        be32(n_code),                 # nCodeSlots
        be32(len(code_bytes)),        # codeLimit
        bytes([32]),                  # hashSize = SHA-256
        bytes([2]),                   # hashType = 2 (SHA-256)
        bytes([0]),                   # platform
        bytes([12]),                  # pageSize = 2^12
        be32(0),                      # spare2
        be32(0),                      # scatterOffset
        be32(0),                      # teamOffset
    ])
    assert len(hdr) == 88, len(hdr)

    blob = hdr + ident + b"\0"
    if ent_offset:
        # 特殊槽从 hashOffset 往前排，slot 5 在最前
        ent_hash = hashlib.sha256(PREV_ENT[0]).digest() if PREV_ENT else b"\0" * 32
        blob += ent_hash
    blob += hashes
    blob = be32(0) + blob[4:]
    blob = blob[:4] + be32(len(blob)) + blob[8:]
    return blob


PREV_ENT = []


def sign_file(path: str, entitlements: bytes = b"") -> None:
    data = open(path, "rb").read()
    filetype, segments, sig_off, ncmds = parse_macho(data)

    # 去掉已有签名：从 codeLimit 处截断
    if sig_off is not None:
        sig_dataoff, sig_datasize = struct.unpack("<II", data[sig_off + 8:sig_off + 16])
        data = data[:sig_dataoff]
        filetype, segments, sig_off, ncmds = parse_macho(data)

    code = data
    ident = path.rsplit("/", 1)[-1].encode()

    enc = build_entitlements_blob(entitlements) if entitlements else b""
    if enc:
        PREV_ENT.clear()
        PREV_ENT.append(enc)

    cd = build_codedirectory(code, ident, len(enc))
    req = build_requirements()

    # SuperBlob 布局：header + 索引(每个8字节) + 各 blob
    count = 2 if enc else 1
    idx_size = 12 + count * 8
    off_cd = idx_size
    off_req = off_cd + len(cd)
    off_ent = off_req + len(req)

    parts = [be32(CSMAGIC_EMBEDDED_SIGNATURE), be32(0), be32(count)]
    parts.append(be32(0) + be32(off_cd))          # slot 0 = CodeDirectory
    parts.append(be32(1) + be32(off_req))         # slot 1 = Requirements(空)
    if enc:
        parts.append(be32(5) + be32(off_ent))     # slot 5 = Entitlements
    parts += [cd, req, enc if enc else b""]
    blob = b"".join(parts)
    blob = be32(CSMAGIC_EMBEDDED_SIGNATURE) + be32(len(blob)) + blob[8:]

    # 追加到文件末尾
    data_off = len(data)
    out = bytearray(data)
    out += blob
    out += b"\0" * ((16 - len(out) % 16) % 16)

    # 更新 __LINKEDIT.filesize
    for seg in segments:
        if seg["name"] == "__LINKEDIT":
            new_size = len(out) - seg["fileoff"]
            struct.pack_into("<Q", out, seg["cmd_off"] + 48, new_size)

    # 写入 (或追加) LC_CODE_SIGNATURE
    blob16 = struct.pack("<IIII", LC_CODE_SIGNATURE, 16, data_off, len(blob))
    if sig_off is not None:
        out[sig_off:sig_off + 16] = blob16
    else:
        # 没有现成的签名命令：追加到 load commands 末尾（需要 sizeofcmds 有空位）
        raise RuntimeError(
            "该文件没有预留 LC_CODE_SIGNATURE，追加需要重排 load commands；"
            "请用 clang 链接时加 -Wl,-adhoc_codesign（lld 支持）"
        )

    open(path, "wb").write(bytes(out))
    print(f"signed {path} ({len(blob)} bytes signature)")


def verify(path: str) -> int:
    data = open(path, "rb").read()
    filetype, segments, sig_off, ncmds = parse_macho(data)
    if sig_off is None:
        print("[x] 没有 LC_CODE_SIGNATURE")
        return 1
    data_off, size = struct.unpack("<II", data[sig_off + 8:sig_off + 16])
    if data_off + size > len(data):
        print(f"[x] 签名越界 ({data_off}+{size} > {len(data)})")
        return 1
    blob = data[data_off:data_off + size]
    magic, length, count = struct.unpack(">III", blob[:12])
    if magic != CSMAGIC_EMBEDDED_SIGNATURE:
        print(f"[x] SuperBlob magic 错: {magic:#x}")
        return 1
    print(f"[ok] 签名有效：{size} 字节，{count} 个子块")
    return 0


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    if sys.argv[1] == "--verify":
        sys.exit(verify(sys.argv[2]))
    ent = b""
    if len(sys.argv) > 3 and sys.argv[2] == "--entitlements":
        ent = open(sys.argv[3], "rb").read()
        sign_file(sys.argv[4], ent)
    else:
        sign_file(sys.argv[1])
