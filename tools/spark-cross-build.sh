#!/bin/sh
# spark-cross-build.sh —— 用系统 clang + ld64.lld 交叉编译 iOS dylib
#
# 不依赖 Linux 容器：clang 本身支持 -target arm64-apple-ios，
# ld64.lld 支持 -adhoc_codesign，两步就能产出已签名的 Mach-O。
#
# 为什么需要这条路
# ---------------
# 常规路线依赖 Theos 的 darwin clang-16 / ld64，需要：
#   · 一套 125MB 的 rootfs 工具链
#   · App 以 root 运行（否则写不了 .theos/）
#   · 足够的磁盘与内存
#
# clang 本身就能产出 arm64 Mach-O（实测
# `clang -target arm64-apple-ios15.0 -c` 得到 cffaedfe），
# 配合 ld64.lld 的 -Wl,-adhoc_codesign 可以直接签名。
# 所以只要有一个 SDK 的 .tbd 桩，就能在没有 Theos 的情况下
# 编出可加载的 dylib。
#
# 局限（必须知道）
# ---------------
#   · 只能编 dylib / 单文件，不能跑 Logos（.x 需要 perl 预处理，做得到但要另接）
#   · 需要 SDK 的 tbd（可从本项目的 theos/sdks 里取）
#   · 最终产物的架构取决于 SDK 桩，通常是 arm64
#
# 用法
# ----
#   spark-cross-build.sh <源文件.m> <输出.dylib> [SDK根目录]
#
# 退出码
# ------
#   0 成功；2 缺依赖；3 编译失败；4 签名失败

set -eu

SRC="${1:-}"
OUT="${2:-}"
SDKROOT="${3:-}"

die() { printf '\033[1;31m[x] %s\033[0m\n' "$1" >&2; exit "${2:-1}"; }
say() { printf '\033[1;36m==> %s\033[0m\n' "$1"; }
ok()  { printf '\033[1;32m[ok] %s\033[0m\n' "$1"; }

[ -n "$SRC" ] || die "用法：$0 <源文件.m> <输出.dylib> [SDK根目录]" 1
[ -f "$SRC" ] || die "源文件不存在：$SRC" 1
[ -n "$OUT" ] || die "缺少输出路径" 1

TARGET_TRIPLE="arm64-apple-ios15.0"
MIN_IOS="15.0"

say '检查交叉编译依赖'
CLANG=$(command -v clang || true)
LDLLD=$(command -v ld64.lld || command -v ld.lld || true)
[ -n "$CLANG" ] || die "找不到 clang" 2
[ -n "$LDLLD" ] || die "找不到 ld64.lld（需要 lld）" 2
ok "clang: $CLANG"
ok "链接器: $LDLLD"

# SDK 桩：优先用参数给的，否则找 libSystem.tbd
TBDPATH=""
if [ -n "$SDKROOT" ]; then
  TBDPATH=$(find "$SDKROOT" -name 'libSystem.tbd' 2>/dev/null | head -1 || true)
fi
if [ -z "$TBDPATH" ]; then
  for base in /var/mobile/Documents/Workbench/Toolchain/theos/sdks \
              /var/mobile/Documents/Rein/tools/theos-full/sdks; do
    [ -d "$base" ] || continue
    TBDPATH=$(find "$base" -name 'libSystem.tbd' 2>/dev/null | head -1 || true)
    [ -n "$TBDPATH" ] && break
  done
fi
[ -n "$TBDPATH" ] || die "找不到 libSystem.tbd（指定 SDK 根目录，或先展开工具链）" 2
ok "SDK 桩: $TBDPATH"

SDKLIBDIR=$(dirname "$TBDPATH")
SDKSDIR=$(dirname "$SDKLIBDIR")   # 形如 .../usr

say '编译'
OUTDIR=$(dirname "$OUT")
[ -d "$OUTDIR" ] || mkdir -p "$OUTDIR"

set +e
"$CLANG" \
  -target "$TARGET_TRIPLE" \
  -miphoneos-version-min="$MIN_IOS" \
  -dynamiclib \
  -fuse-ld=lld \
  -fobjc-arc \
  -nostdlib \
  -Wl,-no_implicit_dylibs \
  -Wl,-no_fixup_chains \
  -O2 -DNDEBUG \
  -isysroot "$SDKSDIR" \
  -L"$SDKLIBDIR" \
  -Wl,-adhoc_codesign \
  -o "$OUT" \
  "$SRC" 2>&1
rc=$?
set -e

if [ $rc -ne 0 ]; then
  die "编译失败（exit $rc）" 3
fi
[ -f "$OUT" ] || die "编译没有产出文件" 3
ok "产物 $(ls -lh "$OUT" | awk '{print $5}')"

say '校验 Mach-O'
MAGIC=$(head -c 4 "$OUT" | od -An -tx1 | tr -d ' \n')
if [ "$MAGIC" != "cffaedfe" ]; then
  die "产物不是 64 位 arm64 Mach-O（magic=$MAGIC）" 3
fi
ok "magic $MAGIC（arm64 Mach-O）"

say '校验签名'
SIGSCRIPT=""
for cand in "$(dirname "$0")/macho_sign.py" \
            /usr/share/spark/macho_sign.py; do
  [ -f "$cand" ] && { SIGSCRIPT="$cand"; break; }
done
if [ -n "$SIGSCRIPT" ] && command -v python3 >/dev/null 2>&1; then
  python3 "$SIGSCRIPT" --verify "$OUT" || die "签名校验失败" 4
else
  # 没有校验脚本时退化为「查文件里有没有 LC_CODE_SIGNATURE」
  if python3 - "$OUT" <<'PY'
import struct, sys
d = open(sys.argv[1], 'rb').read()
ncmds = struct.unpack('<I', d[16:20])[0]
off = 32
for _ in range(ncmds):
    cmd, size = struct.unpack('<II', d[off:off+8])
    if cmd == 0x1d:
        sys.exit(0)
    off += size
sys.exit(1)
PY
  then ok "含 LC_CODE_SIGNATURE"
  else die "产物没有代码签名，iOS 无法加载" 4
  fi
fi

say '完成'
echo "产物：$OUT"
