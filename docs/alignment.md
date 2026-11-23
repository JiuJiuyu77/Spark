# Workbench 对照检查表

> 以**代码实际存在**为准。上一版多处标 ✅ 但代码里没有，已逐项核实更正。

## 〇、运行时结构（本轮最大修正）

对照 `CodexApp.app/TheosRuntime`（73MB 压缩 / **572MB 解压**）确认：
它**不是**「只放 Theos」，而是一个完整根文件系统。

```
TheosRuntime/
├── bin/          基础命令
├── usr/bin/      clang-16(107K) ld64(2.3M) ldid(221K) make dpkg-deb perl
├── usr/lib/      llvm-16/(libLLVM-16.dylib 108MB) + perl5(96.9M) + 30 个 dylib
├── theos/        makefiles + bin/logos.pl + sdks/
└── etc/ var/ Library/
```

**只打 `theos/` 会怎样**（我们之前就是这样）：
- 链接找不到 `ld64` → 构建必失败
- `.x` 预处理找不到 `perl` / `perl5` → 失败
- `make package` 找不到 `dpkg-deb` → 失败

**已修正**：`scripts/pack-runtime.sh` 产出 rootfs，
`SPToolchainInstaller` / `SPBuilder` 路径自适应（`usr/bin` 优先，`bin` 兜底）。
产物 125.1MB / 解压 511MB / 15978 条目，已上传 Spark-Runtime。

---

## A. Rein（DSH.app）—— 编译能力基准

| # | Rein | Workbench | 状态 |
|---|---|---|---|
| A0 | Darwin 工具集（clang/ld64/ldid/perl/dpkg-deb） | 已打进 rootfs 运行时包 | ✅ 本轮修复 |
| A1 | Theos 多 SDK（16.5/17.0/26.5） | 内置 16.5+17.0 | ✅ |
| A2 | Arkari OLLVM | 23.1.1 的 7 个 pass + 兼容旧版 cff | ✅ |
| A3 | radare2 / mt-macho / 注入 dylib | 逆向页（按需下载） | ✅ |
| A4 | ldid / insert_dylib 补签 | 构建与注入都调 | ✅（A0 已解决依赖） |
| A5 | 父进程自毁守护 | `SPSessionReapAllChildren` | ✅ |
| A6 | 内存遥测 | 编译期间每 15 秒采样 | ✅ 本轮完成 |
| A7 | 注入脚本结构化 JSON | `SPARK-RESULT {...}` | ✅ 本轮完成 |
| A8 | pnpm 插件市场 | 不做（无 AI 生态） | — |
| A9 | Python 3.13 | 按需下载 | ✅ |
| A10 | node22 | 按需下载 Node 24.5.0 | ✅ |

## B. TrollFools —— 注入器基准

| # | TrollFools | Workbench | 状态 |
|---|---|---|---|
| B1 | 走 LaunchServices 枚举 App | **`SPAppEnumerator`**：动态调 `LSApplicationWorkspace`，失败回退文件系统；图标走 LS 缓存 | ✅ **本轮完成** |
| B2 | 主 Mach-O 选择（跳过 PlugIns/framework） | 同规则 | ✅ |
| B3 | 路径规范化 @executable_path | 同 | ✅ |
| B4 | 准备 CydiaSubstrate | 多路径查找 + 可从 libsubstrate.dylib 构造 | ✅ |
| B5 | CoreTrust 绕过 | 三种别名查找；缺失时**明确告警**「TrollStore 下会闪退」 | ✅ 本轮增强 |
| B6 | 注入后重启目标 App | `launchctl kill` + `open` | ✅ 本轮完成 |
| B7 | 备份 / 恢复 | `.sparkbak` | ✅ |
| B8 | 卸载注入 | 「卸载注入（恢复备份）」菜单 | ✅ |

## C. Dylix —— 历史对照（**非基准**，工具链不迁移）

| # | Dylix | Workbench | 状态 |
|---|---|---|---|
| C1 | 项目模板 | tweak / app | ✅ |
| C2 | 语法着色 + 查找替换 | 有 | ✅ |
| C3 | 构建记录 / 报告 | report.json + 历史 | ✅ |
| C4 | 双 SDK | 16.5 + 17.0 | ✅ |
| C5 | 三种 deb 布局 | rootful / rootless / roothide | ✅ |
| C6 | Git | 状态/暂存/提交/diff/历史/远端/推送 | ✅ |
| C7 | IPA 头文件导出 | 有 | ✅ |
| C8 | Mach-O 静态分析 | rabin2 + 自写字节解析 | ✅ |
| C9 | 离线崩溃分析 | 9 类模式识别 | ✅ |
| C10 | 局域网工作台 | 自建 HTTP + 内嵌网页 | ✅ |
| C11 | 存储空间管理 | 六分类 + 清理 | ✅ |
| C12 | 分享接收 | Share Extension | ✅ |
| C13 | SDK 导入 | 有 | ✅ |
| C14 | 内嵌 Linux 终端 | 不做 | — |
| C15 | AI 助手 | 不做 | — |

---

## 状态汇总

```
A 组 11 项：10 ✅ / 1 不做
B 组  8 项：8 ✅（本轮补齐 B1、B5、B6）
C 组 15 项：13 ✅ / 2 不做
```

## 仍需人工操作

1. **工具链包已上传**，但 App 要能下载需确认 Release 附件可见性
2. **CoreTrust 绕过**：需自行放置 `ct_bypass` 二进制（开源可编译，不便随包分发）
3. 真机验证：装 v1.6.0 后确认「设置 → 工具链」显示就绪、能编译出 tweak
