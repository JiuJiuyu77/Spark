# 设计说明

## 1. 为什么是「原生 App」而不是网页

Rein 本身是原生 App（DSH 二进制 + 内嵌 node）驱动 AI 改代码，界面上大量是**长任务 + 实时日志**。
纯网页沙盒拿不到这些能力：

| 需求 | 网页 | 原生 |
|---|---|---|
| 起子进程跑 make | ✗（没有 posix_spawn） | ✓ |
| 读全盘（theos-root / SDK） | ✗ | ✓（去掉沙盒） |
| 后台长时间编译不被杀 | ✗ | ✓ |
| 系统级分享/文件提供者 | 弱 | ✓ |

所以选 Objective-C + UIKit，目标 iOS 15+（Rein 的最小版本一致）。

## 2. 模块边界

```
SPSession          子进程原语：posix_spawn + pipe + 行读 + 取消（TERM→KILL 整组）
   ↑
SPBuilder          编排：脚本生成 → 执行 → 产物收集 → 诊断
   ↑                        ↑
SPToolchain        探测     ShareKit/model.js（判定逻辑的唯一真相）
   ↑
UI 层              Projects / Project / Console / Toolchain / Reverse
```

**SPSession 不用 NSTask**：iOS 上 `NSTask` 不存在。这里用 `posix_spawn` 配
`POSIX_SPAWN_SETPGROUP`，让 make 派生的所有进程落在同一个进程组里，取消时
`kill(-pid)` 一次带走，避免编译中断后留下僵尸 clang。

**读管道用两条串行队列**：stdout/stderr 各一条，按 `\n` 切行后丢回主队列。
末尾不完整的一行也会 flush 出来（编译器的最后一行经常没有换行符）。

## 3. 选项 → make 的映射

| 选项 | 产生的变量/参数 |
|---|---|
| arch=both | `ARCHS="arm64 arm64e"` |
| format=rootless | `THEOS_PACKAGE_SCHEME=rootless` |
| debug=true | `DEBUG=1 THEOS_DEBUG=1 OPTFLAG="-O0 -g"` |
| debug=false | `DEBUG=0 OPTFLAG="-O2 -g"`（strip 时 `-O2`） |
| OLLVM 任一档 | `ADDITIONAL_CCFLAGS` / `ADDITIONAL_OBJCFLAGS` 里追加 `-mllvm -irobf …` |
| finalize | make 目标从 `all` 变 `package`，并加 `FINALPACKAGE=1` |
| clean | 目标前加 `clean`，并 `rm -rf .theos/_ .theos/obj packages` |

`FINALPACKAGE=1` 下不能再带 `DEBUG=1`，否则 deb 里会塞进调试符号 —— 这是 Rein 的
`boot.js` 同款处理，不一致会让包体积莫名其妙翻倍。

## 4. 工具链探测顺序

对每个组件，按「用户指定 → Rein 目录 → App 包内」依次找第一份存在的：

| 组件 | 候选路径 |
|---|---|
| Theos | `tools/theos-full` → `tools/theos-local` → `theos-root/theos` → `theos` |
| SDK | `<theos>/sdks/iPhoneOS*.sdk` → `sdks-store/iPhoneOS*.sdk` |
| Darwin 工具 | `tools/theos-root/usr/bin`（要真有 clang/ld64） |
| OLLVM | `tools/ollvm`（要真有 `bin/clang`） |
| 逆向 | `tools/reverse/bin`（rabin2 或 mt-macho 至少一个） |

SDK 选择：默认取版本号最大的；也可以在工具链页指定。

## 5. 失败诊断表

`ShareKit/src/model.js` 的 `diagnose()` 与 `SPBuilder` 的 `diagnoseFailureFromLines:`
共用同一张规则表（关键词 → 中文建议 → 分类）。分类用于以后做「一键修复」入口：
`toolchain` 跳工具链页，`config` 跳选项，`ollvm` 建议关混淆重试。

## 6. CI 为什么不用 Theos

Theos 在 macOS 上还要额外装 toolchain 与 SDK；而 runner 自带 Xcode 和
iPhoneOS SDK，`xcrun clang -target arm64-apple-ios15.0` 直接就能产出可用的
Mach-O。仓库因此**不包含 .xcodeproj**：编译步骤写在 `build.yml` 里，PR 的
diff 也就只剩源码本身。
