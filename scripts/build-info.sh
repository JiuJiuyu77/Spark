#!/bin/sh
# build-info.sh —— 生成 include/build-info.mk，把版本号 / git 描述 / 构建时间写进 App
# 用法：sh scripts/build-info.sh [版本号]
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p include

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
	VERSION="$(sed -n 's/^Version: *//p' control | head -1)"
fi
[ -n "$VERSION" ] || VERSION="1.0.0"

GIT="$(git describe --tags --always --dirty 2>/dev/null || echo dev)"
WHEN="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

cat > include/build-info.mk <<EOF
SP_VERSION := $VERSION
SP_GIT_DESCRIBE := $GIT
SP_BUILD_DATE := $WHEN
SP_EXTRA_CFLAGS := -DSP_VERSION_STR='"$VERSION"' -DSP_GIT_DESCRIBE='"$GIT"' -DSP_BUILD_DATE='"$WHEN"'
EOF

echo "生成 include/build-info.mk"
cat include/build-info.mk
