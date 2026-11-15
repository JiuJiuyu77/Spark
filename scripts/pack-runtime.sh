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

say "1/6 基础命令 → bin/"
BASIC="cat chgrp chown cp date dd dir echo false gunzip gzexe gzip kill ln ls \
mkdir mknod mktemp mv pwd rm rmdir sleep sync touch true uname which env"
n=0
for b in $BASIC; do
	if [ -f "$THEOS_ROOT/usr/bin/$b" ]; then
		cp "$THEOS_ROOT/usr/bin/$b" "$PKGROOT/bin/" 2>/dev/null && n=$((n+1))
	fi
done
ok "$n 个"

say "2/6 编译工具 → usr/bin/"
# 这些是 Realm 的编译链核心，一个都不能少
TOOLS="clang-16 clang++-16 clang clang++ clang-cpp ld64 ld ld-classic \
as ar ranlib nm strip lipo ldid ldid2 install_name_tool \
otool otool-classic ObjectDump bitcode_strip \
make dpkg-deb dpkg dpkg-query dpkg-split dpkg-realpath dpkg-statoverride \
tar gzip gunzip unzip zip ditto fakeroot plutil PlistBuddy \
sed awk grep egrep fgrep find xargs basename dirname tee head tail \
chmod chflags chcon apply"
n=0
MISSING=""
for b in $TOOLS; do
	if [ -f "$THEOS_ROOT/usr/bin/$b" ]; then
		cp "$THEOS_ROOT/usr/bin/$b" "$PKGROOT/usr/bin/" 2>/dev/null && n=$((n+1))
	else
		MISSING="$MISSING $b"
	fi
done
ok "$n 个"
[ -n "$MISSING" ] && warn "缺失:$MISSING"

# perl（logos.pl / nic.pl 必需）
if [ -f "$THEOS_ROOT/usr/bin/perl" ]; then
	cp "$THEOS_ROOT/usr/bin/perl" "$PKGROOT/usr/bin/" && ok "perl"
else
	die "找不到 perl —— logos.pl 无法运行，.x 文件无法编译"
fi

say "3/6 clang 运行时 → usr/lib/"
# clang 资源（头文件）
if [ -d "$THEOS_ROOT/usr/lib/clang" ]; then
	cp -R "$THEOS_ROOT/usr/lib/clang" "$PKGROOT/usr/lib/" && ok "lib/clang"
fi

# LLVM 运行库（clang-16 是薄壳，真正代码在 libLLVM-16.dylib）
if [ -d "$THEOS_ROOT/usr/lib/llvm-16" ]; then
	mkdir -p "$PKGROOT/usr/lib/llvm-16/lib"
	cp -R "$THEOS_ROOT/usr/lib/llvm-16/lib/"*.dylib "$PKGROOT/usr/lib/llvm-16/lib/" 2>/dev/null || true
	cp -R "$THEOS_ROOT/usr/lib/llvm-16/bin" "$PKGROOT/usr/lib/llvm-16/" 2>/dev/null || true
	cp -R "$THEOS_ROOT/usr/lib/llvm-16/share" "$PKGROOT/usr/lib/llvm-16/" 2>/dev/null || true
	ok "lib/llvm-16"
fi

# 去重：libLLVM.dylib 与 libLLVM-16.dylib 同内容（各 108MB）
#
# 注意：**不能用符号链接**！TrollStore 安装时执行
#   ldid -s Payload/Spark.app
# 它会递归签名目录里每个文件，读到符号链接时同样报
# "Unknown header magic" 导致整个安装失败（已实测踩坑）。
# 用硬链接：两个名字指向同一份数据，ldid 看到的是普通文件。
LLVM_LIB="$PKGROOT/usr/lib/llvm-16/lib"
if [ -f "$LLVM_LIB/libLLVM.dylib" ] && [ -f "$LLVM_LIB/libLLVM-16.dylib" ]; then
	A=$(stat -c %s "$LLVM_LIB/libLLVM.dylib" 2>/dev/null || echo 0)
	B=$(stat -c %s "$LLVM_LIB/libLLVM-16.dylib" 2>/dev/null || echo 1)
	if [ "$A" = "$B" ]; then
		rm -f "$LLVM_LIB/libLLVM.dylib"
		if ln "$LLVM_LIB/libLLVM-16.dylib" "$LLVM_LIB/libLLVM.dylib" 2>/dev/null; then
			ok "libLLVM 去重（硬链接，省 108MB）"
		else
			# 硬链接不可用（跨卷）时宁可复制，也不能留符号链接
			cp "$LLVM_LIB/libLLVM-16.dylib" "$LLVM_LIB/libLLVM.dylib"
			warn "硬链接失败，改为复制（包体 +108MB）"
		fi
	fi
fi

# 其它运行库（dpkg / perl 依赖）
count=0
for f in "$THEOS_ROOT"/usr/lib/*.dylib; do
	[ -e "$f" ] || continue
	cp "$f" "$PKGROOT/usr/lib/" 2>/dev/null && count=$((count+1))
done
[ "$count" -gt 0 ] && ok "$count 个 dylib"

# perl5 模块（96MB，logos 需要）
if [ -d "$THEOS_ROOT/usr/lib/perl5" ]; then
	cp -R "$THEOS_ROOT/usr/lib/perl5" "$PKGROOT/usr/lib/" && ok "lib/perl5"
fi

say "4/6 Theos 本体 → theos/"
mkdir -p "$PKGROOT/theos/sdks"
for part in makefiles bin lib vendor include templates mod extras package.json Prefix.pch LICENSE.md; do
	[ -e "$THEOS_FULL/$part" ] && cp -R "$THEOS_FULL/$part" "$PKGROOT/theos/" 2>/dev/null
done
# SDK：优先 17.0 + 16.5，有 26.5 也带上
SDKN=0
for sdk in "$THEOS_FULL"/sdks/iPhoneOS*.sdk; do
	[ -d "$sdk" ] || continue
	cp -R "$sdk" "$PKGROOT/theos/sdks/" 2>/dev/null && SDKN=$((SDKN+1))
done
ok "Theos + $SDKN 个 SDK"
[ -f "$PKGROOT/theos/bin/logos.pl" ] || die "theos/bin/logos.pl 没拷进来"

say "5/6 权限与 manifest"
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

say "6/6 压缩"
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
