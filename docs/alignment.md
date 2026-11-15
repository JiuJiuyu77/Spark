# Spark 对照检查表（对齐进度）

## A. Rein（DSH.app）—— 编译能力基准

| # | Rein 的能力 | Spark | 状态 |
|---|---|---|---|
| A1 | Theos 多 SDK（16.5/17.0/26.5） | 扫描 + 选择 + 用户导入 | ✅ |
| A2 | Arkari OLLVM 5 pass | 按需下载 + 5 pass 可选 | ✅（包待上传） |
| A3 | radare2 / mt-macho / 注入 dylib | 逆向页全都有 | ✅ |
| A4 | ldid / insert_dylib 补签 | 构建与注入都做 | ✅ |
| A5 | 父进程自毁守护（boot.js） | 进程组 kill | ✅ |
| A6 | 内存遥测 | 构建脚本开头打 vm_stat | ✅ 已补 |
| A7 | 注入脚本输出结构化 JSON | 注入结束打印 {"ok":..,"app":..} | ✅ 已补 |
| A8 | pnpm 插件市场 | 无 | — 不需要（无 AI 生态） |
| A9 | Python 3.13 运行时 | 按需下载 | ✅ |
| A10 | node22 内嵌 | 按需下载 Node 24.5.0 | ✅ |

## B. TrollFools —— 注入器基准

| # | TrollFools | Spark | 状态 |
|---|---|---|---|
| B1 | PROPFIND 式 App 枚举（走 LS） | 文件系统枚举 | ⚠️ 等价但不完全相同 |
| B2 | 主 Mach-O 选择（跳过 PlugIns/framework） | 同规则 | ✅ |
| B3 | 路径规范化 @executable_path | 同 | ✅ |
| B4 | CydiaSubstrate 准备 | 多路径查找 + 自动复制/构造 framework | ✅ 已补 |
| B5 | CoreTrust 绕过 | 依赖 ct_bypass（需自备） | ⚠️ 有提示 |
| B6 | 注入后重启目标 App | killall + open | ✅ 已补 |
| B7 | 备份/恢复 | 有 .sparkbak | ✅ |
| B8 | 卸载（eject）注入的 dylib | 扫描 .sparkbak 并可恢复 | ✅ 已补 |

## C. Dylix —— 工作台基准

| # | Dylix | Spark | 状态 |
|---|---|---|---|
| C1 | 项目模板 | 有（tweak/app） | ✅ |
| C2 | 语法着色 + 查找替换 | 有 | ✅ |
| C3 | 构建记录/产物/报告 | 有 report.json | ✅ |
| C4 | 双 SDK 可选 | 有 | ✅ |
| C5 | 三种 deb 布局 | rootful/rootless/roothide | ✅ |
| C6 | Git（本地 + GitHub/Gitee） | 无 | ❌ 未做 |
| C7 | IPA 头文件导出 | 有 | ✅ |
| C8 | Mach-O 静态分析 / 反汇编 | 有（rabin2 -c） | ✅ |
| C9 | 离线崩溃分析 | 只能看自己生成的报告 | ⚠️ 部分 |
| C10 | 局域网远程工作台（WebDAV/HTTP） | 只有 WebDAV 客户端 | ❌ 未做 |
| C11 | 存储空间管理 | 有 | ✅ |
| C12 | 分享接收 | 有（Share Extension） | ✅ |
| C13 | 按需下载 SDK | 有（导入） | ✅ |
| C14 | 内嵌 Linux 终端 | 无 | — 不打算做 |
| C15 | AI 助手 | 明确不做 | — |

## 本轮已补齐（v1.2.1）

- ✅ B4 CydiaSubstrate：多路径查找（App 内 / 同级 / /Library / /var/jb），
  没有 framework 时用 libsubstrate.dylib 现场构造一个
- ✅ B6 注入后重启目标 App（killall + open）
- ✅ B8 卸载注入：「注入」页右上角 ⋯ → 扫描所有 .sparkbak 并恢复
- ✅ A6 内存遥测：构建脚本开头打印 vm_stat 可用内存
- ✅ A7 结构化 JSON：注入结束打印 {"ok":true,"app":...,"plugins":N,"backup":...}

## 仍待做（按价值排序）

1. **C6 Git**（本地 diff / commit / push GitHub）—— 独立功能，工作量最大
2. **C10 局域网远程工作台**（HTTP 服务 + 浏览器编辑）—— 需要完整的 Web 端
3. **B5 CoreTrust 绕过** —— 依赖外部 ct_bypass，只能给提示
4. **B1 App 枚举走 LaunchServices** —— 现在走文件系统，等价但没有图标缓存
5. **C9 离线崩溃分析** —— 现在只能看 Spark 自己生成的报告
