# Rein（DSH.app）实现逻辑分析

> 目的：把 Rein 的实现细节记录下来，作为 Spark 的行为基准。
> 下面每一条都是读它的实际文件／脚本得出的，不是猜的。

## 1. 启动链路

```
DSH（ObjC 主程序，593KB）
 └─ 读 /var/mobile/Documents/Rein/boot.js
     └─ node22 runtime/app/node_modules/@deepseek-ai/dsh/lib/bin.js
         └─ runCli()
```

`boot.js` 里有两段**很关键**的守护逻辑：

| 机制 | 代码 | 作用 |
|---|---|---|
| 父进程自毁 | `setInterval` 每 2s 检查 `process.ppid !== ORIG_PPID` → `exit(0)` | App 被杀后不留孤儿 node 进程 |
| 内存遥测 | 每 30s 打印 `rss / heapUsed / heapTotal` | 长任务内存泄漏能被发现 |

**Spark 已借鉴**：`SPSession` 取消时整组 `kill(-pid)`，避免留下 clang/ldid 僵尸进程。

## 2. 工具链目录布局（Spark 完全对齐）

```
Rein/tools/
├── theos-full/          完整 Theos（含 SDK 16.5 + 17.0）
├── theos-local/         精简 Theos（只带 16.5）
├── theos-root/          288 个 Darwin 工具（Mach-O arm64）
│   ├── usr/bin/         clang-16 / ld64 / ldid / strip / ar / make…
│   └── usr/lib/         llvm-16/lib/libLLVM-16.dylib（108MB）
├── ollvm/               Arkari LLVM 16.0.6（clang 80MB）
├── reverse/             radare2 6.2.4 + mt-macho / mt-inject-dylib
├── python/              Python 3.13.14
├── pnpm/                pnpm
└── bin/                 logos.pl / nic.pl / dm.pl / fakeroot.sh
```

**体积结论**：全套约 1.0–1.2 GB，其中 theos-root 519MB、SDK 267MB、perl5 95MB。
Spark 的策略是**内置 Theos + 最小编译链**，其余（OLLVM/逆向/完整工具集）按需下载。

## 3. 注入逻辑（`helpers/inject`）

这是 Rein 自己写的 shell 脚本，五个步骤与 TrollFools 同源，但有 **4 个实战经验**：

### 3.1 用 grep -a 而不是 strings 判断是否已注入

```sh
if ! grep -aq "$DYLIB_NAME" "$BIN" 2>/dev/null; then
  insert_dylib --all-yes --inplace "@executable_path/$DYLIB_NAME" "$BIN"
fi
```

原因写得很直白：

> 用 grep 而不是 strings：设备上没有 strings（helpers 里没打进去），
> `set -e` 下一旦命令不存在整脚本就静默退出（踩过：表现为「insert_dylib 失败」但其实没跑到那步）

**Spark 已借鉴**：`SPTrollViewController` 的插入循环改为 `grep -aq` 幂等判断 + `--all-yes`。

### 3.2 可执行名用 PlistBuddy，不用 plutil

```sh
EXE=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$DEST/Info.plist")
[ -n "$EXE" ] || EXE=$(basename "$NAME" .app)     # 必须有兜底
```

> iOS 自带的 plutil 是老版本，不支持 `-extract ... raw`（会把参数当文件路径报 File not found）

**Spark 已借鉴**：`executable` 为空时退回目录名。

### 3.3 重签要覆盖 dylib

```sh
"$LDID" -S "$BIN" 2>/dev/null || "$LDID" -S "$DEST/$DYLIB_NAME" 2>/dev/null || true
```

> insert_dylib 已经移除了旧的 LC_CODE_SIGNATURE，这里用 ldid 重新生成 adhoc 签名
> （TrollStore 靠 CoreTrust 漏洞接受）

**Spark 已借鉴**：补签步骤对主二进制和每个 dylib 都做。

### 3.4 输出结构化 JSON

脚本最后一行固定输出：

```json
{"ok":true,"ipa":"...","bytes":170287,"exe":"Spark","dylib":"ControlAgent.dylib"}
```

调用方不用解析日志，直接读这一行。**这比解析 stdout 可靠得多。**

## 4. OLLVM 接入方式（manifest.json）

```json
{"id":"indbr","flags":["-mllvm","-irobf","-mllvm","--irobf-indbr"]}
```

五个 pass 用 `-mllvm -irobf -mllvm --irobf-xxx` 的形式传。
Rein 的 `install.environment` 里注入三个变量：

```
CA_TOOL_OLLVM_ROOT          → ollvm/
CA_TOOL_OLLVM_CLANG         → ollvm/bin/clang
CA_TOOL_OLLVM_RESOURCE_DIR  → ollvm/lib/clang/16
```

**Spark 已对齐**：`SPToolchainProfile extraEnvironment` 用同样的变量名，
构建脚本里再导出一遍，保证两套环境无缝。

## 5. 版本探测与降级

`sdks-store/` 下有三个 SDK（16.5 / 17.0 / 26.5），`manifest.json` 里带
`minimum_ios` 与 `archive_sha256`。Rein 的选择顺序是**从新到旧**，
但 `iphone:clang:latest:15.0` 里的 `latest` 实际取的是 theos 目录下最新的 SDK。

Spark 的 `pickSDK()` 逻辑不完全相同：**优先选 ≤ 目标版本的最新一个**，
理由是「用新 SDK 编老系统」会引入不必要的 API 面。

## 6. 值得借鉴但我还没做的

| 项 | Rein 的做法 | 要不要做 |
|---|---|---|
| 父进程自毁守护 | boot.js 每 2s 查 ppid | ✅ 已通过进程组 kill 达到类似效果 |
| 内存遥测 | 每 30s 打 rss/heap | 🔲 可以加到构建日志里 |
| 结构化 JSON 输出 | inject 脚本最后一行 | 🔲 注入完成时也可以输出 |
| pnpm 市场 | tools/pnpm + market/*.json | 🔲 暂时不需要（没有 AI/插件生态） |

## 7. 结论

Rein 的**工程经验**（不要用 strings、PlistBuddy 而非 plutil、重签要覆盖 dylib、
父进程自毁）比它的功能列表更值得借鉴 —— 这些都是踩过坑才写下的注释，
Spark 已经把这些逐条落到实现里。
