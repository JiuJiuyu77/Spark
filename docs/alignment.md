# Spark 对照检查表（Rein / TrollFools / Dylix）

> 本表以**代码实际存在**为准，不以「计划过」为准。
> 上一版有若干项标了 ✅ 但代码里没有，本轮已核实并更正。

## 〇、最大缺口：编译链不完整（影响 A 组全部）

**TheosRuntime.tar.gz 里只有 `theos/`（makefiles + logos.pl + 双 SDK），
没有 `bin/` 也没有 `lib/perl5`。**

后果：
- `make` 能跑到编译阶段，但**链接时会找不到 `ld64`** → 构建失败
- `.x` 文件（Logos）需要 `logos.pl`，而它需要 `perl` → **预处理就挂**
- 打 deb 需要 `dpkg-deb` → 也缺

Rein 之所以能跑，是因为它多了 `tools/theos-root/usr/bin`（519MB 的 Darwin 工具集）。

**修复方式（已提供工具）**：`scripts/pack-runtime.sh`
从 Rein 目录切出约 90MB 的编译链包（clang-16 / ld64 / ldid / dpkg-deb / perl + perl5 /
libLLVM-16），上传到 Spark-Runtime 后 App 才能真编译。

---

## A. Rein（DSH.app）—— 编译能力基准

| # | Rein 的能力 | Spark 现状 | 状态 |
|---|---|---|---|
| A0 | Darwin 工具集（clang/ld64/ldid/perl/dpkg-deb） | **包内没有**，只扫 Rein 目录 | ❌ **最大缺口** |
| A1 | Theos 多 SDK（16.5/17.0/26.5） | 内置 16.5+17.0，可导入 | ✅ |
| A2 | Arkari OLLVM | 29 个 pass 可选（23.1.1 fla/cie/cfe + 兼容 16 的 cff） | ✅ |
| A3 | radare2 / mt-macho / 注入 dylib | 逆向页调用（需按需下载） | ✅ |
| A4 | ldid / insert_dylib 补签 | 构建、注入都会调（同样依赖 A0） | ⚠️ 依赖 A0 |
| A5 | 父进程自毁守护 | `SPSessionReapAllChildren` 退出时整组 kill | ✅ |
| A6 | 内存遥测（每 30s 打 rss/heap） | 构建开始时打印一次 + 编译期间每 15s 采样 | ✅ 本轮完成 |
| A7 | 注入脚本结构化 JSON 输出 | 输出 `SPARK-RESULT {...}` 行 | ✅ 本轮完成 |
| A8 | pnpm 插件市场 | 不做（无 AI 生态） | — |
| A9 | Python 3.13 运行时 | 按需下载 | ✅ |
| A10 | node22 内嵌 | 按需下载 Node 24.5.0（带 node-gyp iOS 适配） | ✅ |

## B. TrollFools —— 注入器基准

| # | TrollFools | Spark 现状 | 状态 |
|---|---|---|---|
| B1 | 走 LaunchServices 枚举 App | 文件系统枚举（等价，无图标缓存） | ⚠️ 可用 |
| B2 | 主 Mach-O 选择（跳过 PlugIns/framework） | 同规则 | ✅ |
| B3 | 路径规范化 @executable_path | 同 | ✅ |
| B4 | 准备 CydiaSubstrate | 多路径查找 + 可从 libsubstrate.dylib 现场构造 | ✅ |
| B5 | CoreTrust 绕过 | 依赖外部 ct_bypass，缺失时提示 | ⚠️ 有提示 |
| B6 | 注入后重启目标 App | `launchctl kill` + `open` | ✅ 本轮完成 |
| B7 | 备份 / 恢复 | `.sparkbak` | ✅ |
| B8 | 卸载注入（eject） | 「卸载注入（恢复备份）」菜单 | ✅ |

## C. Dylix —— 工作台基准

| # | Dylix | Spark 现状 | 状态 |
|---|---|---|---|
| C1 | 项目模板 | tweak / app | ✅ |
| C2 | 语法着色 + 查找替换 | 有 | ✅ |
| C3 | 构建记录 / 产物 / 报告 | report.json + 历史 | ✅ |
| C4 | 双 SDK | 16.5 + 17.0 | ✅ |
| C5 | 三种 deb 布局 | rootful / rootless / roothide | ✅ |
| C6 | Git | 状态/暂存/提交/diff/历史/远端/推送 | ✅（仅 GitHub） |
| C7 | IPA 头文件导出 | 有 | ✅ |
| C8 | Mach-O 静态分析 | rabin2 + 自写字节解析 | ✅ |
| C9 | 离线崩溃分析 | 9 类模式识别 + 中文建议 | ✅ |
| C10 | 局域网工作台 | 自建 HTTP + 内嵌网页 | ✅ |
| C11 | 存储空间管理 | 六分类 + 清理 | ✅ |
| C12 | 分享接收 | Share Extension | ✅ |
| C13 | SDK 导入 | 有 | ✅ |
| C14 | 内嵌 Linux 终端 | 不做 | — |
| C15 | AI 助手 | 不做 | — |

---

## 本轮（v1.5.x → v1.6）实际改动

1. **`scripts/pack-runtime.sh`**（新增）—— 切编译链包，这是打通 A0 的前提
2. **A6** 内存遥测：编译期间每 15 秒采样可用内存
3. **A7** 注入结束输出 `SPARK-RESULT {...}` 结构化行
4. **B6** 注入后重启目标 App

## 下一步（按影响排序）

1. **跑 `pack-runtime.sh` 并上传** → 解除 A0，编译能力才真正完整
2. B5 CoreTrust：内置一份 ct_bypass（开源实现可自行编译）
3. B1 改用 LSApplicationWorkspace 枚举，拿真实图标
