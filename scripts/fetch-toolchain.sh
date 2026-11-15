#!/bin/sh
# fetch-toolchain.sh —— 把 Rein 目录里那套编译工具集装进 App 的 Resources/Toolchain
#
# 分级（对应设置里的「工具链」页）：
#   CORE  必带：Theos 本体 + make/ldid/ld64/clang 最小集  → 内置进 ipa（约 600KB~5MB）
#   EXTRA 可选：OLLVM / radare2 / 完整 lsdk 工具集          → App 内按需下载
#
# 只做「拷贝 + 去重 + 瘦身」，不改动源目录。仓库里不存这些二进制。
# CI：TOOLCHAIN_SOURCE 指向预先上传的 core.tar.gz（只含 CORE 部分）。
#
# 用法：
#   sh scripts/fetch-toolchain.sh [/var/mobile/Documents/Rein]
#   TOOLCHAIN_SOURCE=https://.../toolchain.tar.gz sh scripts/fetch-toolchain.sh
#
# 产出：Native/Resources/Toolchain/  （首次启动由 SPToolchainInstaller 展开到 Documents）
set -eu

ROOT="${1:-${TOOLCHAIN_SOURCE:-/var/mobile/Documents/Rein}}"
OUT="Native/Resources/Toolchain"
# 只打包 CORE（Theos + 最小编译链），其余由 App 内下载
CORE_ONLY="${CORE_ONLY:-1}"

say() { printf '\033[1;36m==> %s\033[0m\n' "$1"; }
warn() { printf '\033[1;33m[!] %s\033[0m\n' "$1"; }

# 支持从 tar.gz 拉取
if printf '%s' "$ROOT" | grep -q '^https\?://'; then
	say "下载工具链包 $ROOT"
	mkdir -p "$OUT"
	curl -fL --retry 3 -o /tmp/spark-toolchain.tar.gz "$ROOT"
	tar xzf /tmp/spark-toolchain.tar.gz -C "$OUT" --strip-components=1 2>/dev/null || tar xzf /tmp/spark-toolchain.tar.gz -C "$OUT"
	rm -f /tmp/spark-toolchain.tar.gz
	say "完成（来自远程包）"
	exit 0
fi

[ -d "$ROOT" ] || { warn "找不到 Rein 目录：$ROOT"; exit 1; }
say "从 $ROOT 收集工具链"

rm -rf "$OUT"
mkdir -p "$OUT/bin" "$OUT/lib" "$OUT/theos"

copy() { # copy <相对路径> <目标>
	src="$ROOT/$1"
	[ -e "$src" ] || { warn "跳过（不存在）$1"; return 0; }
	du -sh "$src" 2>/dev/null | awk -v n="$1" '{printf "    %-58s %s\n", n, $1}'
	cp -R "$src" "$2" 2>/dev/null || warn "复制失败 $1"
}

# ---- 1. Darwin 交叉编译工具（clang/ld64/ldid/strip/ar/make/tar/dpkg…）----
say "1/6 交叉编译工具"
mkdir -p "$OUT/bin"
# CORE 模式只保留编译链路必需的那几个，其余由 App 按需下载
CORE_BINS="make ldid ld64 ld clang-16 clang++-16 clang clang++ ar strip tar gzip "
CORE_BINS="$CORE_BINS cp mv rm mkdir chmod chown ln basename dirname cat tee unzip dpkg"
if [ -d "$ROOT/tools/theos-root/usr/bin" ]; then
	for f in "$ROOT"/tools/theos-root/usr/bin/*; do
		[ -f "$f" ] || continue
		base="$(basename "$f")"
		if [ "$CORE_ONLY" = "1" ]; then
			case " $CORE_BINS " in
				*" $base "*) : ;;   # 在名单里，保留
				*) continue ;;
			esac
		fi
		case "$base" in
			perlbug|perldoc|perlivp|perlthanks|perl5.*|pod2*|splain|cpan*|prove|corelist|enc2xs|instmodsh|json_pp|libnetcfg|piconv|pstruct|psed|zipdetails) continue ;;
		esac
		cp "$f" "$OUT/bin/" 2>/dev/null || true
	done
	du -sh "$OUT/bin" | awk '{print "    bin 小计 " $1}'
else
	warn "没有找到 theos-root/usr/bin（真机编译会不可用）"
fi

# ---- 2. clang 运行时（libLLVM 去重）----
say "2/6 clang 运行时"
L="$ROOT/tools/theos-root/usr/lib"
for d in "llvm-16/lib" "clang" ""; do
	[ -d "$L/$d" ] || continue
	mkdir -p "$OUT/lib/$d"
	# 用 rsync 风格手工复制，libLLVM.dylib 与 libLLVM-16.dylib 内容相同，只留一份并做符号链接
	for f in "$L/$d"/*; do
		[ -e "$f" ] || continue
		[ -d "$f" ] && continue
		b="$(basename "$f")"
		[ "$b" = "libLLVM.dylib" ] && continue
		cp "$f" "$OUT/lib/$d/" 2>/dev/null || true
	done
	if [ -f "$L/$d/libLLVM-16.dylib" ] && [ ! -e "$OUT/lib/$d/libLLVM.dylib" ]; then
		ln -sf libLLVM-16.dylib "$OUT/lib/$d/libLLVM.dylib"
	fi
done
# clang 资源目录（头文件/内建头）
[ -d "$L/clang" ] && cp -R "$L/clang" "$OUT/lib/" 2>/dev/null || true
du -sh "$OUT/lib" | awk '{print "    lib 小计 " $1}'

# ---- 3. perl 模块（logos.pl / nic.pl 依赖）----
say "3/6 perl 模块"
[ -d "$L/perl5" ] && { mkdir -p "$OUT/lib"; cp -R "$L/perl5" "$OUT/lib/" 2>/dev/null || true; }
du -sh "$OUT/lib/perl5" 2>/dev/null | awk '{print "    perl5 " $1}'

# ---- 4. Theos 本体（macOS makefiles / logos.pl / nic.pl / vendor）----
say "4/6 Theos 本体"
TH=""
for c in "$ROOT/tools/theos-full" "$ROOT/tools/theos-local"; do
	[ -d "$c" ] && { TH="$c"; break; }
done
if [ -n "$TH" ]; then
	rm -rf "$OUT/theos"
	mkdir -p "$OUT/theos"
	for part in makefiles bin lib vendor include templates mod extras package.json; do
		[ -e "$TH/$part" ] && cp -R "$TH/$part" "$OUT/theos/" 2>/dev/null || true
	done
	# SDK 不内置（用户自行导入）
	du -sh "$OUT/theos" | awk '{print "    theos 小计 " $1}'
else
	warn "没有找到 Theos 本体"
fi

# ---- 5. OLLVM ----
say "5/6 OLLVM"
if [ "$CORE_ONLY" = "1" ]; then
	say "  CORE 模式跳过 OLLVM（App 内按需下载）"
elif [ -d "$ROOT/tools/ollvm" ]; then
	mkdir -p "$OUT/ollvm"
	cp -R "$ROOT"/tools/ollvm/* "$OUT/ollvm/" 2>/dev/null || true
	du -sh "$OUT/ollvm" | awk '{print "    ollvm 小计 " $1}'
else
	warn "没有找到 OLLVM"
fi

# ---- 6. 逆向工具 ----
say "6/6 逆向工具"
if [ "$CORE_ONLY" = "1" ]; then
	say "  CORE 模式跳过逆向工具（App 内按需下载）"
elif [ -d "$ROOT/tools/reverse" ]; then
	mkdir -p "$OUT/reverse"
	cp -R "$ROOT"/tools/reverse/* "$OUT/reverse/" 2>/dev/null || true
	du -sh "$OUT/reverse" | awk '{print "    reverse 小计 " $1}'
else
	warn "没有找到逆向工具"
fi

# ---- 清单 ----
say "生成清单"
{
	echo "{"
	echo "  \"format\": 2,"
	echo "  \"builtAt\": \"$(date -u '+%Y-%m-%dT%H:%M:%SZ')\","
	printf '  "theos": "%s",\n' "$(basename "${TH:-none}")"
	printf '  "binCount": %s,\n' "$(ls "$OUT/bin" 2>/dev/null | wc -l | tr -d ' ')"
	echo "  \"sdksIncluded\": false,"
	echo "  \"coreOnly\": $CORE_ONLY,"
	echo "  \"notes\": \"由 scripts/fetch-toolchain.sh 生成；SDK 需用户自行导入\""
	echo "}"
} > "$OUT/manifest.json"

say "完成"
du -sh "$OUT" | awk '{print "总大小 " $1}'
