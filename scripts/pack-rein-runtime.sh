#!/bin/sh
# pack-rein-runtime.sh —— 从 Rein(DSH.app) 切出完整运行时，对齐它的目录结构
#
# 为什么需要它
# -----------
# Spark 之前只带了 darwin 工具链（theos-root），而 Rein 的运行时是
# 「ishd 守护进程 + Alpine 容器 + darwin 工具链 + 各类按需运行时」。
# 缺了 ishd 和 alpine-rootfs，App 里的 Linux 侧命令根本起不来 ——
# 这就是「运行时无法启动」的根因。
#
# Rein 的目录（实测于 DSH.app）：
#   helpers/ishd           1.6M   启动 Linux 容器的守护进程（darwin arm64）
#   libvdso.so.elf                容器用的 vdso
#   RootfsPatch.bundle    17K     对 Alpine rootfs 的增量修补
#   alpine-rootfs        8.1M     最小 Alpine 用户空间
#   theos-root           的        darwin 工具链（clang-16/ld64/ldid/…）
#   sdks                 的        iPhoneOS 16.5 / 17.0 / 26.5
#   node22               75M
#   python-runtime       34.7M
#   pnpm                 16M
#   reverse              56.1M   逆向工具
#   ollvm                165.7M  混淆编译器
#   runtime-app.tgz      95.1M   按需运行时包
#   vendor-libs.tar.gz   20.5K
#   plugin-src / patches / svg2png / untar.js
#
# 用法
# ----
#   sh scripts/pack-rein-runtime.sh <DSH.app 路径> <输出目录>
#
# 产物
# ----
#   runtimes/SparkReinRuntime.tar.gz
#   解压后是 ReinRuntime/ ，内含上述全部目录

set -e

SRC="${1:-}"
OUTDIR="${2:-./runtimes}"
OUT_NAME="${OUT_NAME:-ReinRuntime}"

die() { printf '\033[1;31m[x] %s\033[0m\n' "$1" >&2; exit 1; }
say() { printf '\033[1;36m==> %s\033[0m\n' "$1"; }
ok()  { printf '\033[1;32m[ok] %s\033[0m\n' "$1"; }
warn(){ printf '\033[1;33m[!] %s\033[0m\n' "$1"; }

[ -n "$SRC" ] || die "用法：$0 <DSH.app 路径> <输出目录>"
[ -d "$SRC" ] || die "目录不存在：$SRC"

case "$OUTDIR" in /*) ;; *) OUTDIR="$(pwd)/$OUTDIR" ;; esac
mkdir -p "$OUTDIR"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
DEST="$WORK/$OUT_NAME"
mkdir -p "$DEST"

# 必须项：缺任何一个运行时都起不来
say '复制启动必需项'
for part in helpers libvdso.so.elf RootfsPatch.bundle alpine-rootfs; do
    if [ ! -e "$SRC/$part" ]; then
        warn "缺失必需项：$part"
        continue
    fi
    cp -R "$SRC/$part" "$DEST/" 2>/dev/null || warn "复制失败：$part"
    ok "$part"
done

# helpers 里只需要运行时相关的，ControlAgent 之类一并带上（体积很小）
if [ -d "$DEST/helpers" ]; then
    chmod -R 755 "$DEST/helpers" 2>/dev/null || true
fi

say '复制工具链与 SDK'
for part in theos-root theos-min sdks; do
    [ -d "$SRC/$part" ] || { warn "跳过（不存在）：$part"; continue; }
    cp -R "$SRC/$part" "$DEST/" 2>/dev/null || warn "复制失败：$part"
    ok "$part"
done

say '复制按需运行时（体积较大）'
for part in node22 python-runtime pnpm reverse ollvm runtime-app.tgz \
            vendor-libs.tar.gz plugin-src patches svg2png untar.js; do
    [ -e "$SRC/$part" ] || { warn "跳过（不存在）：$part"; continue; }
    cp -R "$SRC/$part" "$DEST/" 2>/dev/null || warn "复制失败：$part"
    ok "$part"
done

# 校验：运行时能不能起来取决于这几样
say '校验启动必需项'
MISSING=""
for part in helpers/ishd alpine-rootfs theos-root/usr/bin/clang-16 sdks/iPhoneOS16.5.sdk; do
    [ -e "$DEST/$part" ] || MISSING="$MISSING $part"
done
if [ -n "$MISSING" ]; then
    die "缺少启动必需项：$MISSING"
fi
ok "启动必需项齐全"

# ishd 必须是可执行的 darwin 二进制
MAGIC=$(head -c 4 "$DEST/helpers/ishd" 2>/dev/null | od -An -tx1 | tr -d ' \n')
case "$MAGIC" in
    cffaedfe|cefaedfe) ok "ishd magic $MAGIC（Mach-O）" ;;
    *) die "ishd 不是 Mach-O（magic=$MAGIC）" ;;
esac

# 写一份清单，App 侧据此判断运行时是否完整
say '生成清单'
SDKLIST=$(ls "$DEST/sdks" 2>/dev/null | tr '\n' ' ')
SIZE=$(du -sm "$DEST" | cut -f1)
cat > "$DEST/manifest.json" <<EOF
{
  "format": 1,
  "id": "rein-runtime",
  "layout": "与 Rein(DSH.app) 对齐",
  "uncompressedMB": $SIZE,
  "sdks": "$SDKLIST",
  "required": [
    "helpers/ishd",
    "alpine-rootfs",
    "theos-root/usr/bin/clang-16",
    "sdks/iPhoneOS16.5.sdk"
  ],
  "env": {
    "THEOS": "\${ROOT}/theos-root/theos",
    "PATH": "\${ROOT}/helpers:\${ROOT}/theos-root/usr/bin",
    "DYLD_LIBRARY_PATH": "\${ROOT}/theos-root/usr/lib:\${ROOT}/theos-root/usr/lib/llvm-16/lib",
    "PERL5LIB": "\${ROOT}/theos-root/usr/lib/perl5"
  }
}
EOF
ok "manifest.json（未压缩 ${SIZE} MB）"

say '压缩'
PKG="$OUTDIR/SparkReinRuntime.tar.gz"
rm -f "$PKG"
tar cf "$WORK/pkg.tar" -C "$WORK" "$OUT_NAME"
python3 - "$WORK/pkg.tar" "$PKG" <<'PY' || gzip -9 -c "$WORK/pkg.tar" > "$PKG"
import gzip, shutil, sys
with open(sys.argv[1], 'rb') as f, gzip.open(sys.argv[2], 'wb', compresslevel=6) as g:
    shutil.copyfileobj(f, g, 512 * 1024)
PY
rm -f "$WORK/pkg.tar"

FINAL=$(du -sm "$PKG" | cut -f1)
SHA=$(sha256sum "$PKG" 2>/dev/null | cut -d' ' -f1 || echo "(no sha256sum)")
echo
ok "完成：$PKG"
printf '  压缩 %s MB / 解压 %s MB\n  sha256 %s\n\n' "$FINAL" "$SIZE" "$SHA"
echo "下一步：把包传到 Spark-Runtime 的 Release，然后 App 侧"
echo "        在「设置 → 工具链 → 从文件导入」里选择它。"
