# Spark 对照检查表（对齐进度）

## A. Rein（DSH.app）—— 编译能力基准

| # | Rein 的能力 | Spark | 状态 |
|---|---|---|---|
| A1 | Theos 多 SDK（16.5/17.0/26.5） | 扫描 + 选择 + 用户导入 | ✅ |
| A2 | Arkari OLLVM 5 pass | 按需下载 + 5 pass 可选 | ✅（包待上传） |
| A3 | radare2 / mt-macho / 注入 dylib | 逆向页全都有 | ✅ |
| A4 | ldid / insert_dylib 补签 | 构建与注入都做 | ✅ |
| A5 | 父进程自毁守护（boot.js） | 进程组 kill | ✅ |
| A6 | 内存遥测（每 30s 打 rss/heap） | 无 | ❌ 未做 |
| A7 | 注入脚本输出结构化 JSON | 无（解析日志） | ❌ 未做 |
| A8 | pnpm 插件市场 | 无 | — 不需要（无 AI 生态） |
| A9 | Python 3.13 运行时 | 按需下载 | ✅ |
| A10 | node22 内嵌 | 按需下载 Node 24.5.0 | ✅ |

## B. TrollFools —— 注入器基准

| # | TrollFools | Spark | 状态 |
|---|---|---|---|
| B1 | PROPFIND 式 App 枚举（走 LS） | 文件系统枚举 | ⚠️ 等价但不完全相同 |
| B2 | 主 Mach-O 选择（跳过 PlugIns/framework） | 同规则 | ✅ |
| B3 | 路径规范化 @executable_path | 同 | ✅ |
| B4 | CydiaSubstrate 准备 | ⚠️ 只插入加载命令，**没有真的复制 framework** | ❌ **缺口** |
| B5 | CoreTrust 绕过 | 依赖 ct_bypass（需自备） | ⚠️ 有提示 |
| B6 | 注入后重启目标 App | 无 | ❌ 未做 |
| B7 | 备份/恢复 | 有 .sparkbak | ✅ |
| B8 | 卸载（eject）注入的 dylib | 无 | ❌ 未做 |

## C. Dylix —— 工作台基准

| # | Dylix | Spark | 状态 |
|---|---|---|---|
| C1 | 项目模板 | 有（tweak/app） | ✅ |
| C2 | 语法着色 + 查找替换 | 有 | ✅ |
| C3 | 构建记录/产物/报告 | 有 report.json | ✅ |
| C4 | 双 SDK 可选 | 有 | ✅ |
| C5 | 三种 deb 布局 | rootful/rootless/roothide | ✅ |
| C6 | Git（本地 + GitHub/Gitee） | 状态/暂存/提交/diff/历史/远端/推送 | ✅ 已做（GitHub） |
| C7 | IPA 头文件导出 | 有 | ✅ |
| C8 | Mach-O 静态分析 / 反汇编 | 有（rabin2 -c） | ✅ |
| C9 | 离线崩溃分析 | 只能看自己生成的报告 | ⚠️ 部分 |
| C10 | 局域网远程工作台 | 自带 HTTP 服务 + 内嵌网页（编辑/构建） | ✅ 已做 |
| C11 | 存储空间管理 | 有 | ✅ |
| C12 | 分享接收 | 有（Share Extension） | ✅ |
| C13 | 按需下载 SDK | 有（导入） | ✅ |
| C14 | 内嵌 Linux 终端 | 无 | — 不打算做 |
| C15 | AI 助手 | 明确不做 | — |

## 优先级建议（下一轮）

1. **B4 CydiaSubstrate** —— 不复制 framework 的话，注入后 tweak 根本不会加载，这是功能缺口
2. **B6 注入后重启目标 App** —— 否则用户以为失败
3. **A7 结构化 JSON 输出** —— 让上层能可靠判断结果
4. **B8 卸载注入** —— 现在只能手工改名 .sparkbak
5. **A6 内存遥测** —— 长任务（编译大工程）内存爆了能提前看到
6. **C6 Git** —— 这个是独立功能，工作量最大
