#!/bin/sh
# pack-runtime.sh —— 切出一个可独立分发的「编译根文件系统」
#
# 结构对照（参考 CodexApp.app/TheosRuntime，73MB 压缩 / 572MB 解压）：
#
#   <包根>/
#   ├── bin/           基础命令（cat cp mv chmod …）
#   ├── usr/bin/       clang-16 / ld64 / ldid / make / dpkg-deb / perl
#   ├── usr/lib/       libLLVM-16 / clang 资源 / perl5 / libcrypto …
#   ├── sbin/ etc/ var/ Library/
#   ├── theos/         Theos 本体（makefiles + bin/logos.pl + sdks/）
#   └── manifest.json
#
# 为什么必须是这个结构：
#   1. Theos 的 makefiles 里 `_CC = $(THEOS)/toolchain/.../clang-16`，
#      找不到就退回 PATH 里的 clang —— 我们的 bin 必须在 PATH 里
#   2. logos.pl 需要 perl 与 perl5 模块，否则 .x 文件预处理直接失败
#   3. dpkg-deb 用来打 deb，缺了 make package 就停在打包前一步
#   4. libLLVM-16.dylib 与 libLLVM.dylib 是两个 108MB 的**同内容副本**，
#      ClangApp 也只留一份，必须去重否则包翻倍
#
# 用法：
#   sh scripts/pack-runtime.sh <Rein目录> <输出目录>
#
# 产物：
#   runtimes/SparkTheosRuntime.tar.gz
#   runtimes/manifest.json

set -e

REIN="${1:-/var/mobile/Documents/Rein}"
OUTDIR="${2:-./runtimes}"
# 转成绝对路径：脚本中途会 cd，相对路径会指错地方
case "$OUTDIR" in
    /*) ;;
    *) OUTDIR="$(pwd)/$OUTDIR" ;;
esac
OUT_NAME="${OUT_NAME:-TheosRuntime}"

die() { printf '\033[1;31m[✗] %s\033[0m\n' "$1" >&2; exit 1; }
say() { printf '\033[1;36m==> %s\033[0m\n' "$1"; }
ok()  { printf '\033[1;32m[ok] %s\033[0m\n' "$1"; }
warn() { printf '\033[1;33m[!] %s\033[0m\n' "$1"; }

[ -d "$REIN" ] || die "Rein 目录不存在: $REIN"

# Rein 有两套：theos-full（makefiles+SDK）与 theos-root（Darwin 工具集）
THEOS_FULL="$REIN/tools/theos-full"
THEOS_ROOT="$REIN/tools/theos-root"
[ -d "$THEOS_FULL" ] || die "找不到 $THEOS_FULL"
[ -d "$THEOS_ROOT/usr/bin" ] || die "找不到 $THEOS_ROOT/usr/bin"

mkdir -p "$OUTDIR" || die "无法创建输出目录 $OUTDIR"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
PKGROOT="$WORK/$OUT_NAME"
mkdir -p "$PKGROOT"/bin "$PKGROOT"/usr/bin "$PKGROOT"/usr/lib "$PKGROOT"/usr/sbin \
         "$PKGROOT"/sbin "$PKGROOT"/etc "$PKGROOT"/var "$PKGROOT"/Library

# ---------------------------------------------------------------
# 全量内嵌：整个 theos-root 原样带走，不再手工挑白名单
#
# 之前是手工列 TOOLS=...，结果只带了 43 个工具（Rein 有 288 个），
# 缺的那些在特定场景下才会暴露（比如 otool/bitcode_strip/
# ldid2/dpkg-split），排查成本很高。
# 现在整目录复制：usr/bin、usr/lib、usr/share、etc、sbin 全要，
# 唯一的取舍是不带注释里明确不需要的东西。
# ---------------------------------------------------------------

say "1/5 全量复制 theos-root → usr/"
# helpers 必须有：里面是 bash（shell 本体）与 ldid 等。
# 少了它 posix_spawn 会找不到可执行的 shell，
# 表现是「退出码 -1、耗时 0 秒」，与编译失败极难区分。
for sub in bin sbin usr etc helpers; do
    [ -d "$THEOS_ROOT/$sub" ] || continue
    cp -R "$THEOS_ROOT/$sub/." "$PKGROOT/$sub/" 2>/dev/null || warn "复制 $sub 有失败项"
    n=$(find "$PKGROOT/$sub" -type f 2>/dev/null | wc -l | tr -d ' ')
    ok "$sub（累计 $n 个文件）"
done

# 顶层 bin 也补一份基础命令（有些脚本按 /bin 找）
if [ -d "$THEOS_ROOT/bin" ]; then
    cp -R "$THEOS_ROOT/bin/." "$PKGROOT/bin/" 2>/dev/null || true
fi

# 校验：编译链必需项一个都不能少
say "2/5 校验编译链"
MISSING=""
for b in clang-16 ld64 ldid make dpkg-deb perl; do
    if [ -x "$PKGROOT/usr/bin/$b" ] || [ -x "$PKGROOT/bin/$b" ]; then
        ok "$b"
    else
        MISSING="$MISSING $b"
    fi
done
[ -z "$MISSING" ] || die "编译链缺必需工具：$MISSING"

# 统计实际带了多少工具（对齐 Rein 的 288 个）
BINCOUNT=$(ls "$PKGROOT/usr/bin" 2>/dev/null | wc -l | tr -d ' ')
ok "usr/bin 共 $BINCOUNT 个工具"

say "3/5 Theos 本体 + SDK"

# 与 Rein 的实际布局对齐（核对过 DSH.app）：
#   theos-root/theos/           ← Theos 本体（makefiles/bin/extras…）
#   theos-root/theos/sdks/      ← **空目录**（Rein 里就是空的）
#   sdks/iPhoneOS*.sdk          ← SDK 独立放在顶层
# 之前我按「SDK 在 theos/sdks 下」布局，与实际不符。
# 这里两种都放：theos/sdks 里软链到顶层 sdks，兼容两种查找方式。

THEOS_SRC="$THEOS_ROOT/theos"
[ -d "$THEOS_SRC" ] || THEOS_SRC="$THEOS_FULL"
[ -d "$THEOS_SRC" ] || die "找不到 Theos 本体（theos-root/theos 或 theos-full）"

mkdir -p "$PKGROOT/theos" "$PKGROOT/sdks"
for part in makefiles bin lib vendor include templates mod extras package.json Prefix.pch LICENSE.md; do
    [ -e "$THEOS_SRC/$part" ] && cp -R "$THEOS_SRC/$part" "$PKGROOT/theos/" 2>/dev/null
done

# SDK：优先从 theos 自带目录取，其次从顶层 sdks/
SDKN=0
for sdk in "$THEOS_SRC"/sdks/iPhoneOS*.sdk "$REIN"/sdks/iPhoneOS*.sdk; do
    [ -d "$sdk" ] || continue
    name=$(basename "$sdk")
    # 已复制过就跳过（两个来源可能重复）
    [ -d "$PKGROOT/sdks/$name" ] && continue
    cp -R "$sdk" "$PKGROOT/sdks/" 2>/dev/null && SDKN=$((SDKN + 1))
done
ok "Theos 本体 + $SDKN 个 SDK"
[ -f "$PKGROOT/theos/bin/logos.pl" ] || die "theos/bin/logos.pl 没拷进来"

# theos/sdks 指向顶层 sdks（有些 makefile 会直接查 $THEOS/sdks）
rm -rf "$PKGROOT/theos/sdks"
mkdir -p "$PKGROOT/theos/sdks"
for d in "$PKGROOT/sdks"/*.sdk; do
    [ -d "$d" ] || continue
    ln -sf "../../sdks/$(basename "$d")" "$PKGROOT/theos/sdks/$(basename "$d")" 2>/dev/null || true
done

# 逐个 SDK 校验：从网络路径复制大目录会静默失败，
# 曾出现「iPhoneOS17.0.sdk 存在但是空目录」，copy 返回 0、目录存在，
# 直到编译才报找不到 SDKSettings.json。
for d in "$PKGROOT"/sdks/iPhoneOS*.sdk; do
    [ -d "$d" ] || continue
    name=$(basename "$d")
    cnt=$(find "$d" -type f 2>/dev/null | wc -l | tr -d ' ')
    if [ ! -f "$d/SDKSettings.json" ]; then
        die "$name 缺 SDKSettings.json（复制失败，可能是空目录）"
    fi
    if [ "$cnt" -lt 1000 ]; then
        die "$name 只有 $cnt 个文件（正常 5000+，复制不完整）"
    fi
    ok "$name（$cnt 个文件）"
done

say "4/5 权限与 manifest"
chmod -R 755 "$PKGROOT/bin" 2>/dev/null || true
chmod -R 755 "$PKGROOT/usr/bin" 2>/dev/null || true

# ---- 关键：把 shell 脚本「降级」为普通文件 ----
# TrollStore 用 `ldid -s Payload/Spark.app` 对整个目录签名，
# 遇到 #! 开头的脚本会报 "Unknown header magic" 而整体失败。
# 这些脚本（egrep/fgrep/gunzip/gzexe/dpkg-realpath）都不是编译必需的，
# 去掉可执行位即可，路径仍在但不会被执行。
SCRIPTS_DEMOTED=0
find "$PKGROOT" -type f 2>/dev/null | while read -r f; do
	[ "$(head -c 2 "$f" 2>/dev/null)" = '#!' ] || continue
	chmod 644 "$f" 2>/dev/null && echo "  降级 $(basename "$f")"
done
SCRIPTS_DEMOTED=$(find "$PKGROOT" -type f ! -perm -u+x 2>/dev/null | wc -l | tr -d ' ')
ok "非可执行文件 $SCRIPTS_DEMOTED 个（含被降级的脚本）"

STAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
SDKLIST=$(ls "$PKGROOT/theos/sdks" 2>/dev/null | tr '\n' ' ')
cat > "$PKGROOT/manifest.json" <<EOF
{
  "format": 1,
  "id": "theos-runtime",
  "packedAt": "$STAMP",
  "layout": "rootfs",
  "paths": {
    "bin": "PATH 前缀 1",
    "usr/bin": "PATH 前缀 2（clang-16 / ld64 / ldid / make / dpkg-deb / perl）",
    "usr/lib": "DYLD_LIBRARY_PATH（libLLVM-16 / clang 资源 / perl5）",
    "theos": "THEOS 根（makefiles + logos.pl + sdks）"
  },
  "sdks": "$SDKLIST",
  "note": "解压到 Documents/Spark/Toolchain 后，构建脚本会拼 PATH=<root>/usr/bin:<root>/bin，THEOS=<root>/theos，DYLD_LIBRARY_PATH=<root>/usr/lib:<root>/usr/lib/llvm-16/lib，PERL5LIB=<root>/usr/lib/perl5"
}
EOF

say "5.5/6 清理空壳 bundle（否则 TrollStore 的 ldid -s 会报 Unknown header magic）"
if [ -f "$(dirname "$0")/fix-bundles.py" ]; then
	python3 "$(dirname "$0")/fix-bundles.py" "$PKGROOT" || warn "清理脚本执行失败"
else
	warn "找不到 fix-bundles.py，跳过（可能导致安装失败）"
fi

say "5/5 压缩"
PKG="$OUTDIR/SparkTheosRuntime.tar.gz"
rm -f "$PKG"
# 必须先 tar 再 gzip：busybox 的 `tar czf` 与 `tar | gzip` 在低内存设备上会失败
tar cf "$WORK/pkg.tar" -C "$WORK" "$OUT_NAME" || die "tar 失败"
python3 - "$WORK/pkg.tar" "$PKG" <<'PY' || gzip -9 -c "$WORK/pkg.tar" > "$PKG"
import gzip, shutil, sys
with open(sys.argv[1], 'rb') as f, gzip.open(sys.argv[2], 'wb', compresslevel=9) as g:
    shutil.copyfileobj(f, g, 256 * 1024)
PY
rm -f "$WORK/pkg.tar"

SIZE=$(wc -c < "$PKG" | tr -d ' ')
SHA=$(sha256sum "$PKG" 2>/dev/null | cut -d' ' -f1 || echo "(无 sha256sum)")
UNPACKED=$(du -sm "$PKGROOT" 2>/dev/null | cut -f1)

cat > "$OUTDIR/manifest.json" <<EOF
{
  "id": "theos-runtime",
  "file": "SparkTheosRuntime.tar.gz",
  "size": $SIZE,
  "unpackedMB": ${UNPACKED:-0},
  "sha256": "$SHA",
  "packedAt": "$STAMP"
}
EOF

echo
ok "完成"
printf '  文件   %s\n' "$PKG"
printf '  压缩   %.1f MB\n' "$(awk "BEGIN{print $SIZE/1048576}")"
printf '  解压   %s MB\n' "${UNPACKED:-?}"
printf '  sha256 %s\n\n' "$SHA"
echo "下一步："
echo "  gh release upload runtime-v1 $PKG --repo JiuJiuyu77/Spark-Runtime --clobber"
