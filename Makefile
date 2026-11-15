## ReinBuild —— 可视化编译工具
##
## 真机编译（Rein 里直接 make）：
##   THEOS=~/Rein/tools/theos-full make package FINALPACKAGE=1
##
## 交叉验证（语法/类型检查，不需要签名）：
##   make syntax-check
##
## 产物：packages/com.reinbuild.app_<版本>_iphoneos-arm.deb

TARGET := iphone:clang:latest:15.0
ARCHS  := arm64 arm64e

include $(THEOS)/makefiles/common.mk

# 构建信息由 CI 注入（scripts/build-info.sh 会生成 include/build-info.mk）
-include include/build-info.mk

APPLICATION_NAME = ReinBuild

ReinBuild_FILES = $(wildcard Native/ObjC/*.m)
ReinBuild_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore
ReinBuild_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-variable \
                   $(RB_EXTRA_CFLAGS)
ReinBuild_OBJCFLAGS = $(ReinBuild_CFLAGS)
ReinBuild_LIBRARIES = MobileCoreServices
ReinBuild_CODESIGN_FLAGS = -Ssign.plist
ReinBuild_INSTALL_PATH = /Applications
ReinBuild_RESOURCE_DIRS = Native/Resources

include $(THEOS_MAKE_PATH)/application.mk

## ---------------------------------------------------------------------------
## 便捷目标
## ---------------------------------------------------------------------------

after-install::
	install.exec "killall -9 ReinBuild 2>/dev/null || true"

## 只做语法/类型检查：用 SDK 的 clang 逐文件 -fsyntax-only，不链接不签名。
## 在 Linux/macOS 的 CI runner 上也能跑，方便 PR 快速反馈。
syntax-check:
	@echo "==> syntax-check：逐文件语法检查"
	@set -e; \
	SDK="$(THEOS_SDK)"; [ -n "$$SDK" ] || SDK="$$(ls -d $(THEOS)/sdks/iPhoneOS*.sdk 2>/dev/null | tail -1)"; \
	echo "    SDK = $$SDK"; \
	for f in Native/ObjC/*.m; do \
	  printf '    %-40s' "$$f"; \
	  xcrun -sdk iphoneos clang -fsyntax-only -target arm64-apple-ios15.0 -isysroot "$$SDK" \
	        -fobjc-arc -INative/ObjC -Wall -Wno-unused-variable "$$f" 2>/tmp/rb-syn.err \
	    && echo "ok" || { echo "FAIL"; cat /tmp/rb-syn.err; exit 1; }; \
	done
	@echo "==> 全部通过"

## 打印当前会用的构建参数（排查 CI 问题很有用）
print-config:
	@echo "THEOS      = $(THEOS)"
	@echo "THEOS_SDK  = $(THEOS_SDK)"
	@echo "TARGET     = $(TARGET)"
	@echo "ARCHS      = $(ARCHS)"
	@echo "VERSION    = $(RB_VERSION)"
	@echo "GIT        = $(RB_GIT_DESCRIBE)"
