<div align="center">

# Spark

**参考 Rein（DSH.app）复刻的可视化编译工具 —— 一个 iOS 原生 App**

Theos / Logos 一键编译 · OLLVM 混淆 · 逆向工具台 · **巨魔注入器** · **MCP 服务** · 本机 / 远程 / GitHub CI 三种构建

[![build](https://github.com/JiuJiuyu77/Spark/actions/workflows/build.yml/badge.svg)](https://github.com/JiuJiuyu77/Spark/actions/workflows/build.yml)
[![checks](https://github.com/JiuJiuyu77/Spark/actions/workflows/checks.yml/badge.svg)](https://github.com/JiuJiuyu77/Spark/actions/workflows/checks.yml)
![platform](https://img.shields.io/badge/platform-iOS%2015%2B-blue)
![license](https://img.shields.io/badge/license-MIT-green)

</div>

---

## 这是什么

Spark 是一个装在越狱 iPhone 上的**原生 App**，把「写 tweak → 编译 → 打包 → 看日志」整条链路收进手机里。
它参照 Rein 的数据目录（`/var/mobile/Documents/Rein`）里那套工具链设计：**不重复造轮子，只把已有的
Theos / OLLVM / radare2 串起来**，并给它们一个能点的界面。

| 你在 Rein 里做的事 | Spark 里对应的地方 |
|---|---|
| 让 AI 帮你改代码、跑 `make package` | 「项目」页 → 编译按钮 → 控制台实时日志 |
| `tools/theos-full` 多 SDK | 「工具链」页扫描并选 SDK |
| `tools/ollvm` 的 5 个 Arkari pass | 「混淆（OLLVM）」开关 + 强度档位 + 自定义 pass |
| `tools/reverse` 的 radare2 / mt-macho | 「逆向」页：架构、符号、字符串、注入 dylib、重签名 |
| 给别人的 ipa 塞插件的 TrollFools | 「注入」页：巨魔注入器（参考 TrollFools） |
| 让 AI 直接调编译能力 | MCP 服务（`bin/spark-mcp.mjs`，仅 127.0.0.1） |
| 换设备/云端跑长任务 | 「构建目标」：本机 / SSH 远程 / GitHub Actions |

## 界面

```
┌────────┬────────┬────────┬────────┐
│  项目   │  工具链 │  逆向   │  注入   │
├────────┴────────┴────────┴────────┤
│  MyTweak                            [+] │
│  ├ Tweak    rootless deb   3 个源文件    │
│  ├ DemoApp  App            7 个源文件    │
│  └ …                                    │
│                                         │
│        ┏━━━━━━━━━━━━━━━━━━━┓            │
│        ┃  ▶  编译            ┃            │
│        ┗━━━━━━━━━━━━━━━━━━━┛            │
└─────────────────────────────────────────┘
```

控制台页的布局：

```
 编译中…                                 00:42
 ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░░░░░░░░░░░░░
 [ 停止 ]            [ 预览命令 ]
 💡 提示（失败时给出人话解释）
 📦 MyTweak_1.0.0_iphoneos-arm.deb

 ==> 工具链自检
 [ok] make /usr/bin/make
 [ok] THEOS=/var/mobile/Documents/Rein/tools/theos-full
 ==> 开始编译
 > Making all for tweak MyTweak…
 ==> Compiling Tweak.x (arm64)…
```

## 功能一览

### 编译

- **项目识别**：读 `Makefile` 判断 tweak / application / library / tool / bundle；读 `control` 拿包名版本；非 Theos 项目识别 Node / 脚本
- **构建选项**：架构（arm64 / arm64e / 双架构）、包格式（传统 deb / rootless deb / .app / .tipa）、Debug↔Release、clean、`-j` 并行、ldid 补签、strip
- **命令可预览**：任何一次编译都能先「预览命令」，看到的就是将要执行的完整 shell 脚本，可复制、可贴到终端复现
- **失败会说人话**：从输出里认出 `ld: library not found` / 头文件缺失 / 被 OOM kill / Logos 语法错 等 10 多类问题，直接给一句中文建议
- **日志**：虚拟化列表（几万行不卡）、颜色分级、复制、落盘到 `Documents/Spark/logs/`

### OLLVM

与 Rein 的 `tools/ollvm/manifest.json` 一一对应：

| pass | 作用 | clang flags |
|---|---|---|
| `indbr` | 间接跳转 | `-mllvm -irobf -mllvm --irobf-indbr` |
| `icall` | 间接调用 | `-mllvm -irobf -mllvm --irobf-icall` |
| `indgv` | 间接全局 | `-mllvm -irobf -mllvm --irobf-indgv` |
| `cse` | 字符串加密 | `-mllvm -irobf -mllvm --irobf-cse` |
| `cff` | 控制流平坦化 | `-mllvm -irobf -mllvm --irobf-cff` |

预设：**轻度**（indbr+cse）/ **均衡**（+icall）/ **强力**（全部 5 个）/ 自定义。

### 逆向

- Mach-O 架构信息、段与节、导出符号、ObjC 类与方法、导入库
- 字符串扫描、段熵值（判断是否加壳）
- `mt-inject-dylib` 注入（自动备份原文件）、`ldid -S` 重签名

### 构建目标

| 目标 | 怎么跑 | 适合 |
|---|---|---|
| **本机** | App 里直接 `make`（你设备上那套 theos-root 里的 Darwin 工具） | 日常小改动，几十秒出包 |
| **远程** | 生成脚本 → `scp` 到另一台越狱机 → `ssh` 执行 | 手机性能弱 / 想不耽误玩手机 |
| **GitHub CI** | 手机上传 zip → Cloudflare Worker 转 `workflow_dispatch` → macos runner 编译 → 回传产物 | 大工程、多架构、要留档 |

### 巨魔注入器

参考 [Lessica/TrollFools](https://github.com/Lessica/TrollFools)（MIT）的注入流程，
用设备上现成的工具实现「给任意 App 塞 tweak」：

```
选 App → 选插件（dylib/framework/bundle/.deb/.zip）→ 预览计划 → 注入
```

自动完成的 6 步（与 TrollFools 的 `InjectorV3` 一一对应）：

| # | 动作 | 说明 |
|---|---|---|
| 1 | 备份 | `App.app` → `App.app.sparkbak`，注入失败可原样恢复 |
| 2 | 预处理 | `.deb` / `.zip` 自动解出 `dylib / framework / bundle`，过滤系统库 |
| 3 | 规范化路径 | 安装名改成 `@executable_path/…`（沙盒里才找得到） |
| 4 | 准备 Substrate | 复制 `CydiaSubstrate.framework`，tweak 才加载得起来 |
| 5 | 插入加载命令 | `insert_dylib [--weak] --inplace <dylib> <App二进制>` |
| 6 | CoreTrust + 属主 | `ct_bypass` + `chown -R mobile:mobile` |

设备上的工具实测：

```
DSH.app/helpers/insert_dylib                       ✓
Rein/tools/theos-root/usr/bin/install_name_tool    ✓
DSH.app/helpers/ldid                               ✓
Rein/tools/theos-root/usr/bin/chown                ✓
ct_bypass                                          ✗（需自备，见 docs/troll-inject.md）
```

细节与坑见 [docs/troll-inject.md](docs/troll-inject.md)。

### MCP 服务（仅本地 127.0.0.1）

Spark 内置 MCP 服务器，Claude Desktop / Cursor / Zed 可以直接调用：

```bash
node bin/spark-mcp.mjs          # stdio（桌面客户端）
node bin/spark-mcp.mjs --http   # HTTP：http://127.0.0.1:7878/mcp
```

| 工具 | 作用 |
|---|---|
| `spark_doctor` | 工具链体检：Theos / SDK / OLLVM / 注入工具缺什么 |
| `spark_projects` | 扫描并识别项目类型 |
| `spark_read_file` | 读源码（带行数上限） |
| `spark_build_script` | 生成完整 Theos 构建脚本 |
| `spark_inject_plan` | 生成巨魔注入计划 + 脚本 |
| `spark_analyze` | 调 radare2 分析 Mach-O |

> ⚠️ **只监听 127.0.0.1**：监听地址在代码里写死为回环，不提供配置项。
> `startHttpServer({host:'0.0.0.0'})` 直接抛错，非回环请求一律 403。
> 远程使用请走 SSH 隧道：`ssh -L 7878:127.0.0.1:7878 设备`。

细节见 [docs/mcp.md](docs/mcp.md)。

## 仓库结构

```
Spark/
├── Native/                  iOS App（Objective-C，26 个源文件）
│   ├── ObjC/
│   │   ├── main.m / SPAppDelegate.m        入口 + 三 Tab 外壳
│   │   ├── SPProjectsViewController.m      项目列表 / 新建 / 导入
│   │   ├── SPProjectViewController.m       单项目面板（选项 + 快捷操作）
│   │   ├── SPConsoleViewController.m       构建控制台
│   │   ├── SPToolchainViewController.m     工具链探测 / SDK / 远程 / CI 设置
│   │   ├── SPReverseViewController.m       逆向工具台
│   │   ├── SPFileBrowserViewController.m   文件树
│   │   ├── SPEditorViewController.m        带行号 + 语法着色编辑器
│   │   ├── SPLogView.m                     虚拟化日志视图
│   │   ├── SPSession.m                     posix_spawn 子进程 + 管道读行 + 可取消
│   │   ├── SPBuilder.m                     构建编排 / 产物收集 / 失败诊断
│   │   ├── SPToolchain.m                   按 Rein 的目录布局探测
│   │   ├── SPModels.m                      项目 / 选项 / 任务模型
│   │   ├── SPStore.m                       JSON 持久化
│   │   ├── SPSyntax.m                      Logos/ObjC/C/Makefile 高亮
│   │   └── SPTheme.m / SPCompat.m          视觉与基础设施
│   └── Resources/Info.plist
├── ShareKit/                 共享逻辑（App / Worker / CLI 用同一份判定）
│   ├── src/model.js         项目识别、make 参数、脚本生成、错误诊断
│   └── test/model.test.mjs  17 个用例
├── ProjectKit/              注入器 + MCP 逻辑（纯 JS，可测试）
│   ├── src/trollinject.mjs  插件筛选、路径规范化、注入计划与脚本生成
│   ├── src/trolltools.mjs   insert_dylib / ldid / ct_bypass 等工具的发现
│   ├── src/mcp-tools.mjs    6 个 MCP 工具的定义与处理器
│   └── test/                34 个用例（注入 / MCP / 回环约束）
├── Workers/SPCloudWorker.js  Cloudflare Worker：上传 / 派发 / 轮询 / 拉产物
├── bin/spark.mjs            CLI：doctor / projects / script / build / analyze
├── bin/spark-mcp.mjs        MCP 服务器（stdio + HTTP，仅回环）
├── scripts/                 工具链探测、脚本生成、括号体检
├── .github/workflows/       build.yml（macOS 真机构建）+ checks.yml（秒级检查）
├── Makefile / control       自身也是标准 Theos 工程
└── docs/                    设计说明与踩坑记录
```

## 环境要求

| 用在哪儿 | 需要什么 |
|---|---|
| 跑 App | 越狱 iOS 15+，TrollStore / 自签均可；建议有 Rein 的 `theos-root`（Darwin 版 clang/ld64） |
| 跑 CI | 一个 GitHub 仓库（`macos-14` runner 自带 Xcode） |
| 跑 Worker（可选） | Cloudflare 账号 + `wrangler` |

## 快速开始

### 1. 云端构建（不用自己装任何东西）

```bash
git clone https://github.com/JiuJiuyu77/Spark.git
cd Spark

# 看一眼工具链探测能不能认出 Rein 的目录
REIN_ROOT=/var/mobile/Documents/Rein node scripts/detect-toolchain.mjs
```

推到 GitHub 后，Actions 里的 `build` 工作流会自动编译出 `Spark-<版本>-arm64.ipa`。
打 tag 时会自动建 Release：

```bash
git tag v1.0.0 && git push origin v1.0.0
```

### 2. 自己重签安装

CI 产物是 `codesign -s -` 的临时签名，装到真机要换自己的证书：

```bash
unzip Spark-1.0.0-arm64.ipa
codesign -f -s "Apple Development: 你的名字 (XXXXXXXXXX)" \
         --entitlements entitlements.plist Payload/Spark.app
# 或者用 TrollStore / AltStore / 自签工具直接装 .ipa
```

### 3. 真机直接编译（App 内）

1. 打开 Spark → **工具链**，确认 Theos / SDK / Darwin 工具三项是 ✓
2. **项目** 页点 `+` → 新建 tweak 模板，或「从磁盘选择目录」导入已有工程
3. 进项目 → 选好选项 → 点 **编译**
4. 编译完成点产物名可以直接分享 / 存到文件 App

### 4. 命令行（不用打开 App）

```bash
node bin/spark.mjs doctor                       # 体检
node bin/spark.mjs script /var/mobile/MyTweak   # 只打印会执行的脚本
node bin/spark.mjs build  /var/mobile/MyTweak --release --ollvm strong
node bin/spark.mjs analyze /var/mobile/MyTweak/.theos/obj/MyTweak.dylib strings
```

## 远程构建 Worker（可选）

手机端把工程 zip 传上来、Worker 帮你触发 Actions：

```bash
npm i -g wrangler
wrangler kv namespace create JOBS        # 填进 wrangler.toml
wrangler r2 bucket create spark-uploads
wrangler secret put TOKEN                # 手机端要填同一个
wrangler secret put GH_TOKEN             # PAT，需要 actions:write
wrangler deploy
```

接口一览（全部要求 `Authorization: Bearer <TOKEN>`）：

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/health` | 免鉴权健康检查 |
| PUT | `/upload?job=xxx` | 上传工程 zip（默认限 32MB） |
| POST | `/dispatch` | 触发 Actions，body `{job, project, options}` |
| GET | `/status?job=xxx` | 同步 GitHub run 状态 |
| GET | `/log?job=xxx` | 拉完整构建日志 |
| GET | `/artifact?job=xxx` | 302 到产物下载 |
| GET | `/jobs` | 最近任务 |
| DELETE | `/jobs/<id>` | 取消 run |

## 它是怎么工作的

```
        ┌──────────────────────────── iOS App ────────────────────────────┐
        │  项目模型 ──► 选项 ──► 构建脚本生成 ──► posix_spawn(/bin/sh)     │
        │      │                    │                    │               │
        │      │                    │                    ├─► 逐行读管道 ─► 日志视图
        │      │                    │                    └─► 退出码 ─► 失败诊断
        │      │                    └─ 同一份逻辑也用于「预览命令」和 CLI     │
        │      └─ 工具链探测：theos-full / theos-root / ollvm / reverse      │
        └──────────────────────────────────────────────────────────────────┘
                                   │
             ┌─────────────────────┼─────────────────────┐
             ▼                     ▼                     ▼
         本机 make            scp+ssh 远程         Cloudflare Worker
                                                         │
                                                  workflow_dispatch
                                                         ▼
                                                GitHub macos runner
                                                  （真 Xcode 编译）
                                                         │
                                                     artifacts
```

几个刻意的设计选择：

- **不引入第三方依赖**：Rein 环境里没有 Cephei 一类框架的保证，App 只用 Foundation/UIKit，
  Worker 单文件零依赖，CI 不需要 `pod install`。
- **共享一份判定逻辑**（`ShareKit/src/model.js`）：项目类型、make 参数、脚本生成、错误诊断
  在 App / CLI / Worker 三处复用，避免「本地能编 CI 编不过」。
- **命令永远可见**：每个按钮背后都是一段明文 shell，`预览命令` 随时能看、能复制。
- **失败要说人话**：编译器报错原样保留在日志里，但顶部会给一句中文建议。

## 关于沙箱里「跑不了 Mach-O」

开发这个仓库的环境（iSH / Alpine）**无法执行任何 Mach-O 二进制**，所以：

- 本仓库的 `Native/` 代码没有在本机编译过，只做了括号/序列化/单元测试级检查
- 真正编译由 GitHub Actions 的 `macos-14` runner 完成（见 `build.yml` 的 `Compile` 步骤）
- 想本地验证语法可以用 `make syntax-check`（需要 macOS + Xcode）

## 路线图

- [ ] 内建 git 面板（在 App 里 commit / push）
- [ ] 构建产物一键安装（调 dpkg / TrollStore）
- [x] 巨魔注入器（dylib/framework/bundle/.deb/.zip）
- [ ] 注入后自动打进 ipa（离线流水线）
- [x] MCP 服务（6 个工具，仅 127.0.0.1）
- [ ] MCP 工具扩展到「执行构建并回传日志」
- [ ] 多目标同时编译（同一 tweak 编 rootful + rootless）
- [ ] 依赖图（复刻 Rein 里 `rein-graph` 那张交互图）
- [ ] iOS 15 全量回归测试

## 许可

MIT。Theos、OLLVM(Arkari)、radare2 各有自己的许可，请遵守各自的条款。

**关于巨魔注入器**：实现参考了 [TrollFools](https://github.com/Lessica/TrollFools)
（MIT, © 82Flex / Lessica）公开的注入流程，但**未复制其源码**，只复刻步骤并用系统工具实现。
