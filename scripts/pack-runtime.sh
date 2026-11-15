#!/bin/sh
# pack-runtime.sh —— 从 Rein 目录切出可独立分发的运行时包
#
# 为什么需要它：
#   ipa 里只有 Theos 本体（makefiles + logos.pl + SDK）是不够的。
#   真机编译必须有 clang / ld64 / ldid，logos.pl 需要 perl。
#   这些全在 Rein 的 tools/theos-root 里，要单独打成一个包。
#
# 用法：
#   sh scripts/pack-runtime.sh <Rein目录> <输出目录>
#   sh scripts/pack-runtime.sh /var/mobile/Documents/Rein ./runtimes
#
# 产物：
#   runtimes/SparkToolchain.tar.gz    ~90MB  编译链（clang/ld64/ldid/perl 等）
#   runtimes/manifest.json            sha256 + 体积
#
# 可选环境变量：
#   CORE_ONLY=1   只打核心（默认 1）
#   OUT_NAME=...  自定义包内目录名（默认 toolchain）

set -e

REIN="${1:-/var/mobile/Documents/Rein}"
OUTDIR="${2:-./runtimes}"
OUT_NAME="${OUT_NAME:-toolchain}"
CORE_ONLY="${CORE_ONLY:-1}"

die() { printf '\033[1;31m[✗] %s\033[0m\n' "$1" >&2; exit 1; }
say() { printf '\033[1;36m==> %s\033[0m\n' "$1"; }
ok()  { printf '\033[1;32m[ok] %s\033[0m\n' "$1"; }

[ -d "$REIN" ] || die "Rein 目录不存在: $REIN"
ROOT="$REIN/tools/theos-root"
[ -d "$ROOT/usr/bin" ] || die "找不到 $ROOT/usr/bin"

mkdir -p "$OUTDIR"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

say "目标目录: $WORK/$OUT_NAME"
mkdir -p "$WORK/$OUT_NAME/bin" "$WORK/$OUT_NAME/lib"

# ---- 1. 核心可执行文件 ----
# 这些都是 Mach-O arm64，真机上直接能跑
CORE_BINS="make ldid ld64 ld clang-16 clang++-16 clang clang++ \
ar ranlib strip install_name_tool otool otool-classic nm lipo \
tar gzip gunzip unzip zip cp mv rm mkdir chmod chown ln \
basename dirname cat tee head tail sed awk grep find xargs \
dpkg dpkg-deb dpkg-query dpkg-split dpkg-realpath dpkg-statoverride \
plutil PlistBuddy ldid2 ditto fakeroot"
# 过滤出真实存在的
MISSING=""
FOUND=0
for b in $CORE_BINS; do
	if [ -f "$ROOT/usr/bin/$b" ]; then
		cp "$ROOT/usr/bin/$b" "$WORK/$OUT_NAME/bin/" 2>/dev/null && FOUND=$((FOUND + 1)) || MISSING="$MISSING $b"
	else
		MISSING="$MISSING $b"
	fi
done
ok "可执行文件 $FOUND 个"
[ -n "$MISSING" ] && echo "  （缺失:$MISSING）"

# ---- 2. clang 运行时库 ----
for d in clang llvm-16; do
	[ -d "$ROOT/usr/lib/$d" ] && cp -R "$ROOT/usr/lib/$d" "$WORK/$OUT_NAME/lib/" 2>/dev/null && ok "lib/$d"
done

# libLLVM 两份同大小会翻倍，保留 clang 实际依赖的那份
LLVM="$WORK/$OUT_NAME/lib/llvm-16/lib"
if [ -f "$LLVM/libLLVM.dylib" ] && [ -f "$LLVM/libLLVM-16.dylib" ]; then
	if [ "$(stat -c %s "$LLVM/libLLVM.dylib" 2>/dev/null || echo 0)" = \
	     "$(stat -c %s "$LLVM/libLLVM-16.dylib" 2>/dev/null || echo 1)" ]; then
		rm -f "$LLVM/libLLVM.dylib"
		ln -s libLLVM-16.dylib "$LLVM/libLLVM.dylib"
		ok "libLLVM 去重（符号链接）"
	fi
fi

# 其它 dylib（libcrypto / libzstd 等，dpkg 与 clang 会用到）
for f in "$ROOT"/usr/lib/*.dylib; do
	[ -e "$f" ] || continue
	case "$(basename "$f")" in
		libLLVM*) ;;  # 已经处理
		*) cp "$f" "$WORK/$OUT_NAME/lib/" 2>/dev/null || true ;;
	esac
done

# ---- 3. perl + 模块（logos.pl 必需）----
if [ -f "$ROOT/usr/bin/perl" ]; then
	cp "$ROOT/usr/bin/perl" "$ROOT/usr/bin/perlbug" "$WORK/$OUT_NAME/bin/" 2>/dev/null || true
	ok "perl"
fi
[ -d "$ROOT/usr/lib/perl5" ] && cp -R "$ROOT/usr/lib/perl5" "$WORK/$OUT_NAME/lib/" 2>/dev/null && ok "perl5 模块"

# ---- 4. 空目录占位，供 App 侧放按需下载的组件 ----
mkdir -p "$WORK/$OUT_NAME/libexec"

# ---- 5. 权限 ----
chmod -R 755 "$WORK/$OUT_NAME/bin" 2>/dev/null || true

# ---- 6. 打包 ----
STAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
cat > "$WORK/$OUT_NAME/manifest.json" <<EOF
{
  "format": 1,
  "id": "spark-toolchain",
  "packedAt": "$STAMP",
  "source": "$REIN",
  "layout": {
    "bin": "可执行文件（clang-16 / ld64 / ldid / dpkg-deb / perl …）",
    "lib": "运行时库（libLLVM-16 / clang 资源 / perl5）"
  },
  "note": "解压到 Documents/Spark/Toolchain 后，构建脚本会把 bin 加进 PATH、lib 加进 DYLD_LIBRARY_PATH、lib/perl5 加进 PERL5LIB"
}
EOF

PKG="$OUTDIR/SparkToolchain.tar.gz"
say "压缩 → $PKG"
# 用 Python 的 gzip，busybox 的 tar|gzip 管道在低内存设备上会失败
tar cf "$WORK.tar" -C "$WORK" "$OUT_NAME" 2>/dev/null || tar cf "$WORK.tar" -C "$WORK" .
python3 - "$WORK.tar" "$PKG" <<'PY' 2>/dev/null || gzip -9 -c "$WORK.tar" > "$PKG"
import gzip, shutil, sys
with open(sys.argv[1], 'rb') as f, gzip.open(sys.argv[2], 'wb', compresslevel=9) as g:
    shutil.copyfileobj(f, g, 256 * 1024)
PY
rm -f "$WORK.tar"

# ---- 7. manifest ----
SIZE=$(wc -c < "$PKG" | tr -d ' ')
if command -v sha256sum >/dev/null 2>&1; then
	SHA=$(sha256sum "$PKG" | cut -d' ' -f1)
else
	SHA="(无 sha256sum)"
fi
cat > "$OUTDIR/manifest.json" <<EOF
{
  "id": "spark-toolchain",
  "file": "SparkToolchain.tar.gz",
  "size": $SIZE,
  "sha256": "$SHA",
  "packedAt": "$STAMP"
}
EOF

ok "完成：$PKG"
printf '  大小 %s MB\n   sha256 %s\n\n' "$(awk "BEGIN{printf \"%.1f\", $SIZE/1048576}")" "$SHA"
echo "接下来："
echo "  1) 把 $PKG 上传到 Spark-Runtime 的 Release（tag: runtime-v1）"
echo "  2) Spark 设置页「工具链 → 从文件导入工具链」也能直接吃这个包"
