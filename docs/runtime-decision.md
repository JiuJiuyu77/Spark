# 运行时选型：Codex 仓库 vs Rein 本地

实测数据（2025-11，解压对比），结论写在每节末尾。

## 1. Node —— 用 Codex 仓库 ✅

| 项 | Codex 仓库 |
|---|---|
| 版本 | Node **24.5.0** |
| 组件 | npm 11.5.1 / corepack 0.34.0 / node-gyp 11.2.0 |
| iOS 适配 | `<ios-subprocess-xcode-make-shell-sdkroot-v2>` —— **能在 iOS 上跑 node-gyp 编译原生模块** |
| 附带 | `Frameworks/NodeMobile.framework`、`devkit/node/include`（做原生插件要用） |
| 体积 | 28.1 MB |

Rein 里只有 node22（78MB，且没有 node-gyp iOS 适配）。

**决定：Node 一律用 Codex 仓库的 24.5.0。**

## 2. Theos —— 用 Rein 本地 ✅

| 项 | Codex 仓库 | Rein 本地 |
|---|---|---|
| 体积 | 214MB（压缩后 42.6MB） | 114MB |
| SDK | 只有 iPhoneOS**16.5** | iPhoneOS**16.5 + 17.0** |
| 基于 | Procursus 包（53 个），做了 373 个 Mach-O 重定位 | 原生 theos 仓库 + 现成 toolchain |
| 特点 | 自带完整 darwin 工具链（Library/usr/bin 278MB） | 复用 `theos-root/usr/bin` |
| 风险 | 重定位过的二进制，遇到没测到的路径可能挂 | 已知可用（Rein 自己就在用） |

**决定：Theos 用 Rein 本地的。**

理由有三：
1. **多一个 SDK（17.0）** —— 编 iOS 17 目标更稳
2 体积小一半，下载快
3. Rein 自己在用，等于每天都在被验证

Codex 的 Theos 唯一优势是「自带完整工具链」，但那 278MB 我们已经有 `theos-root` 了。

## 3. OLLVM —— 用 Codex 仓库的 23.1.1 ✅（但要改 pass 名）

| 项 | Codex 23.1.1 | Rein 16.0.6 |
|---|---|---|
| LLVM | 23.1.1 | 16.0.6 |
| pass | indbr / icall / indgv / cse / **fla / cie / cfe** | indbr / icall / indgv / cse / **cff** |
| arm64e | **已验证** cse/cie/cfe/fla 兼容 | 未标注 |
| 预设 | strong / balanced / basic | 只有 balanced |
| clang | 98MB | 77MB |

**决定性差异：pass 名不兼容。**

- Rein 用 `--irobf-cff`（Control Flow Flattening）
- Codex 用 `--irobf-fla`（Flattening，新一代实现）+ `cie`（间接调用增强）+ `cfe`（控制流混淆）

两者**不能混用**：用 Codex 的编译器传 `--irobf-cff` 会报 unknown argument。

**决定：**
- 主线用 **Codex 23.1.1**（LLVM 更新、arm64e 已验证、pass 更多）
- Workbench 的 pass 名要跟着换：`cff` → `fla`，并新增 `cie` / `cfe`
- **兼容处理**：设置页里同时提供两套 pass 名，选择编译器时自动切换
  （如果用户自己换了 OLLVM 包，也能用）

## 4. CoreTools —— 用 Codex 仓库 ✅

Codex 的 CoreTools 有 **git 2.39.1 / curl 8.22 / jq / ripgrep / file / diff / patch / zip / unzip**（9.5MB）。

Rein 的 `theos-root/usr/bin` 里虽然也有这些，但是 519MB 全量打包。

**决定：CoreTools 用 Codex 的 9.5MB 精简版**，theos-root 只取编译真正需要的那几个（clang/ld64/ldid/strip/ar/make）。

## 5. 最终组合

| 包 | 来源 | 体积 |
|---|---|---|
| node | **Codex 仓库** | 28.1 MB |
| theos | **Rein 本地**（scripts/pack-runtime.sh 打包） | ~114 MB |
| ollvm | **Codex 仓库**（23.1.1） | 34.7 MB |
| core_tools | **Codex 仓库** | 9.5 MB |
| reverse_tools | **Codex 仓库** | 16.6 MB |
| python | **Codex 仓库** | 10.1 MB |
| build_tools | **Codex 仓库** | 7.2 MB |

只有 **Theos** 用 Rein 本地打包上传（因为 Codex 的版本少一个 SDK 且是重定位二进制），
其余全部用 Codex 仓库 —— 这样 Spark-Runtime 只需要存 Theos 一个包。

## 6. 代码上要跟着改的

1. `ProjectKit/src/runtimes.mjs`：theos 指向 Spark-Runtime，其余指回 Codex 仓库
2. `SPToolchainDownloader.m`：同步条数与 id
3. `ShareKit/src/model.js` 与 `SPModels.m`：pass 名 `cff` → `fla`，新增 `cie` / `cfe`
4. 设置页混淆强度预设跟着调整
