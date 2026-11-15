# 定位修正：Spark = TrollStore 专用的 Rein 类工具

## 两个方向的根本差别

| 维度 | Dylix（自签） | Rein / Spark（巨魔） |
|---|---|---|
| 运行环境 | 普通签名，**必须**在沙盒里想办法 | 有平台权限，**直接**读写全盘 |
| 编译 | 进程内 LLVM（不能 fork） | **真跑 make**（posix_spawn 起子进程） |
| 工具链 | 必须自带整套 LLVM | 用系统/darwin 版工具，可以调外部命令 |
| 注入 | 不是它的目标 | 核心能力（insert_dylib + 补签） |
| 包管理 | 自己造 deb | 直接 `make package` 出 deb |
| 权限 | 受限，要各种绕 | 一次给足，什么都不用绕 |

**结论：Spark 应该按「我什么权限都有」来设计，而不是按「我怎么在沙盒里活下来」。**

## 按 Rein 形态重新校对后的清单

### 1. 编译：应当真跑 make（已对 ✅）

Spark 走 posix_spawn + /bin/sh → make，这是 Rein 的做法，不是 Dylix 的进程内编译。
**但缺一点**：Rein 的 boot.js 会「父进程消失就自毁」，Spark 只在取消时 kill 进程组，
没有「App 被杀后自动清理」的守护。→ **要补**

### 2. 工具链：应该直接调用系统工具（已对 ✅）

- Rein 用 `theos-root/usr/bin` 里的一整套 Darwin 工具，通过 PATH 注入
- Spark 同样通过 PATH + DYLD_LIBRARY_PATH 注入
- **不应当**像 Dylix 那样打包精简 LLVM

### 3. 注入：这是核心，应当最完整（部分对齐）

Rein 的 `helpers/inject` 已经是最好的参照，我们已对齐：
grep -aq 幂等 / PlistBuddy / ldid 覆盖 dylib / 结构化 JSON。

**还没对齐的 Rein 做法**：
- ❌ 父进程守护（见上）
- ❌ Rein 会自己解析依赖路径（`SELF_DIR`），不依赖调用方传 HE LPERS 环境变量
- ❌ Rein 输出的是 ipa（`Payload/App.app` + zip），我们只改原地 .app
  → **巨魔场景下，改原地 .app 反而更对**（TrollStore 直接覆盖安装），这点保留

### 4. 不该照 Dylix 抄的东西（我做了，应当弱化或去掉）

| 我做了什么 | 为什么不该做 |
|---|---|
| SPAutofix（日志解析自动改代码） | Dylix 因为在沙盒里没有 shell，才要「改代码重编」；Spark 能直接看日志 + 手动改，自动改源码风险大于收益 |
| 头文件导出（SPHeaderExport） | 属于「没有调试器时的替代品」，巨魔环境可以直接用 FLEX / radare2 |
| 存储空间六大分类 | 可以有，但不必像 Dylix 那样细（它有沙盒配额压力，我们没有） |

**建议**：SPAutofix 保留但默认关闭（作为「快捷修补」而非主流程），
头文件导出保留在逆向页作为工具之一，不做重点宣传。

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

Dylix 相关的三样（Autofix / 头文件导出 / 细粒度存储）不删，但降级为次要功能。
