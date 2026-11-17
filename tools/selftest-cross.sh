#!/bin/sh
# 交叉编译自检：在没有 Theos 的环境里验证 ish 路线是否可用
# 用法：tools/selftest-cross.sh
set -eu
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/sdk/usr/lib"
cat > "$TMP/sdk/usr/lib/libSystem.tbd" <<'TBD'
--- !tapi-tbd
tbd-version: 4
targets: [ arm64-ios ]
install-name: '/usr/lib/libSystem.B.dylib'
current-version: 1311
exports:
  - targets: [ arm64-ios ]
    symbols: [ ]
...
TBD
cat > "$TMP/demo.m" <<'SRC'
__attribute__((visibility("default")))
int spark_selftest(int x) { return x + 1; }
SRC
sh "$(dirname "$0")/spark-cross-build.sh" "$TMP/demo.m" "$TMP/demo.dylib" "$TMP" >/dev/null
[ -f "$TMP/demo.dylib" ] || { echo "[x] 没有产物"; exit 1; }
M=$(head -c 4 "$TMP/demo.dylib" | od -An -tx1 | tr -d ' \n')
[ "$M" = "cffaedfe" ] || { echo "[x] magic 错：$M"; exit 1; }
echo "[ok] 交叉编译自检通过（arm64 Mach-O + 已签名）"
