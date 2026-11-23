# 定位：Workbench = TrollStore 专用的 Rein 类工具

> **2026-11 更新**：本项目只做 TrollStore / 越狱（平台权限）场景。
> 不追求普通签名可用，也**不迁移 Dylix 的工具链**（进程内 LLVM 那条路线与
> 本项目架构冲突，硬搬只会产生两套并存的构建后端）。
> 下文 Dylix 相关内容仅作历史背景保留，**不作为实现基准**。

## 两个方向的根本差别（历史参考）

| 维度 | Dylix（自签） | Rein / Workbench（巨魔） |
|---|---|---|
| 运行环境 | 普通签名，**必须**在沙盒里想办法 | 有平台权限，**直接**读写全盘 |
| 编译 | 进程内 LLVM（不能 fork） | **真跑 make**（posix_spawn 起子进程） |
| 工具链 | 必须自带整套 LLVM | 用系统/darwin 版工具，可以调外部命令 |
| 注入 | 不是它的目标 | 核心能力（insert_dylib + 补签） |
| 包管理 | 自己造 deb | 直接 `make package` 出 deb |
| 权限 | 受限，要各种绕 | 一次给足，什么都不用绕 |

**结论：Workbench 应该按「我什么权限都有」来设计，而不是按「我怎么在沙盒里活下来」。**

## 按 Rein 形态重新校对后的清单

### 1. 编译：应当真跑 make（已对 ✅）

Workbench 走 posix_spawn + /bin/sh → make，这是 Rein 的做法，不是 Dylix 的进程内编译。
**但缺一点**：Rein 的 boot.js 会「父进程消失就自毁」，Workbench 只在取消时 kill 进程组，
没有「App 被杀后自动清理」的守护。→ **要补**

### 2. 工具链：应该直接调用系统工具（已对 ✅）

- Rein 用 `theos-root/usr/bin` 里的一整套 Darwin 工具，通过 PATH 注入
- Workbench 同样通过 PATH + DYLD_LIBRARY_PATH 注入
- **不应当**像 Dylix 那样打包精简 LLVM

### 3. 注入：这是核心，应当最完整（部分对齐）

Rein 的 `helpers/inject` 已经是最好的参照，我们已对齐：
grep -aq 幂等 / PlistBuddy / ldid 覆盖 dylib / 结构化 JSON。

**还没对齐的 Rein 做法**：
- ❌ 父进程守护（见上）
- ❌ Rein 会自己解析依赖路径（`SELF_DIR`），不依赖调用方传 HE LPERS 环境变量
- ❌ Rein 输出的是 ipa（`Payload/App.app` + zip），我们只改原地 .app
  → **巨魔场景下，改原地 .app 反而更对**（TrollStore 直接覆盖安装），这点保留

### 4. Dylix 相关功能的处置

Dylix 因为「普通签名 + 沙盒」才需要「改源码重编」「进程内 LLVM」这些绕法。
Workbench 有平台权限，这些都不适用。相关模块处置：

| 模块 | 处置 |
|---|---|
| SPAutofix（日志解析自动改代码） | 保留，默认关闭 |
| SPHeaderExport（IPA 头文件导出） | 保留，逆向页工具之一，不重点宣传 |
| 存储空间细分类 | 保留基础版，不做到 Dylix 那种粒度 |

### 5. Rein 有而我们完全没有的（真正的缺口）

| # | Rein 的能力 | 说明 | 优先级 |
|---|---|---|---|
| R1 | **父进程守护 / 孤儿进程清理** | App 被杀后 node/clang 还在跑 | 高 |
| R2 | **SUID/root 执行内置二进制** | TrollStore 弹窗显示「可以 root 权限执行内置二进制」 | 高 |
| R3 | **ipa 打包输出**（Payload/*.app → zip） | 用于「把改好的 App 交回 TrollStore」 | 中 |
| R4 | **构建产物直接安装** | 调 dpkg -i 或交给 TrollStore | 中 |
| R5 | **pnpm / 插件市场** | Rein 有 market/*.json + pnpm | 低（无 AI 生态） |
| R6 | **内存遥测** | boot.js 每 30s 打 rss/heap | 已补（构建脚本） |

### 6. 结论

接下来该做的（按 Rein 而非 Dylix）：
1. **R2 root 执行**：entitlements 已有，但要确保每次起的子进程确实以 uid 0 运行
   → 检查 `posix_spawn` 是否继承 uid，必要时用 `spawnattr_setpersona` 或 setuid
2. **R1 孤儿清理**：SPSession 的进程在 App 退出后要被回收
3. **R3 ipa 打包**：注入完成后可以选择「导出 ipa」
4. **R4 产物安装**：编译出的 deb 一键安装

**明确不做**：进程内 LLVM（Dylix 路线）、ios_system 进程内命令行、capstone 内置反汇编。
反汇编统一走运行时自带的 otool，不重复引入第二套。
