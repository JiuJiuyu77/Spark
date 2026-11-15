# 踩坑记录

这些都是本次实现里真实撞到的，写下来省得下次再踩。

## 1. `ADDITIONAL_CPPFLAGS` 在新版 Theos 会刷警告

实测 Rein 的 `theos-full`（makefiles/legacy.mk:76）对 `ADDITIONAL_CPPFLAGS`
打 deprecate 警告，真正生效的是 `ADDITIONAL_CCFLAGS`。所以 OLLVM flags 要写进
`ADDITIONAL_CCFLAGS` + `ADDITIONAL_OBJCFLAGS`，不要用老名字。

## 2. Theos 会找 `toolchain/<平台>/<目标>/bin/clang`

`makefiles/targets/Linux/iphone.mk:11` 里：

```make
SDKBINPATH ?= $(THEOS)/toolchain/$(THEOS_PLATFORM_NAME)/$(THEOS_TARGET_NAME)/bin
```

真机上要让它指向 Rein 的 `theos-root/usr/bin`，否则报
`toolchain/linux/iphone/bin/clang: No such file or directory`。
真机编译时把 clang **加进 PATH 最前面**就够（Theos 会优先用 PATH 里的）。

## 3. `FINALPACKAGE=1` 与 `DEBUG=1` 冲突

同时给会让 deb 里带调试符号。判定逻辑：`finalize && debug` → 发 `DEBUG=0`。

## 4. 沙箱里任何 Mach-O 都跑不起来

iSH/Alpine 没有 Darwin 兼容层，执行 Mach-O 直接 `Exec format error`。
所以「在本机编译 iOS App」这条路在开发环境里是不通的，必须走 macOS runner。
同理，Flutter / Dart 这类 AOT 产物的 macOS 版也跑不了 —— 这就是为什么 App 选
Objective-C 而不是 Flutter：**开发环境决定技术选型**。

## 5. 括号平衡检查别用正则

`SPSyntax.m` 里有大量正则字符串，例如 `@"\\b0x[0-9a-fA-F]+\\b"`，用正则去剥字符串
会把 `[0-9a-fA-F]` 里的方括号算进去，误报不平衡。正确做法是手写词法扫描
（见 `scripts/check-balance.py`），只剥注释和字符串，再数括号。

## 6. 远程构建别用嵌套 heredoc

`ssh host 'sh -s' <<EOF … EOF` 里如果脚本本身又含 heredoc 或单引号，引号会打架。
改成：本地写临时文件 → `scp` → `ssh host 'sh /tmp/x.sh'` → 远端删掉。

## 7. Worker 的 `workflow_dispatch` 返回 204

204 没有 body，也不返回 run id。之后要按 `workflow/runs?per_page=20` 找
`display_title` 含 job id 的那条。所以派发时把 job id 放进 `inputs.note`
（GitHub 会把 `run-name` 渲染成 display_title）。

## 8. 日志视图不能每次都 reloadData

每个字符都 reload 会掉帧。用 `UICollectionView` + `performBatchUpdates`
只插入新增行；超过上限时才整表 reload，并在滚动到底部时节流（120ms 一次）。
