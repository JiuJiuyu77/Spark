# 巨魔（TrollStore）注入器

> 设计参考 **Lessica/TrollFools**（MIT，3.6k★）。
> 本项目**没有复制它的代码**，而是复刻它公开的注入流程，用设备上现成的
> `insert_dylib` / `install_name_tool` / `ldid` / `ct_bypass` 来实现同样的事。

## TrollFools 的注入流程（我们照着做）

TrollFools 的核心在 `InjectorV3+*.swift` 这几个文件里，流程可以拆成 6 步：

| 步骤 | TrollFools 做了什么 | Workbench 对应实现 |
|---|---|---|
| 1. 预处理 | `.deb` / `.zip` 先解出 `dylib / framework / bundle`，只保留这三类 | `ProjectKit/src/trollinject.mjs: selectPlugins()` |
| 2. 规范化安装路径 | 把绝对路径改成 `@executable_path/…`（否则 App 沙盒里找不到） | `normalizeInstallName()` |
| 3. 准备 CydiaSubstrate | 把 `CydiaSubstrate.framework` 塞进 App，并把插件的依赖改指向它 | `planInjection()` 的「准备 CydiaSubstrate」 |
| 4. 选主 Mach-O | 优先与 `.app` 同名的可执行文件，跳过 `PlugIns/`、`*.framework/` | `pickTargetMachO()` |
| 5. 插入加载命令 | `insert_dylib` 往主二进制里加 `LC_LOAD_DYLIB`（可选 `--weak`） | `injectionScript()` 生成命令 |
| 6. CoreTrust 绕过 + 改属主 | 让 TrollStore 能「就地安装」被改过的包 | `ct_bypass` + `chown -R mobile:mobile` |

## 设备上的工具从哪来

实测 Rein 的目录里已经有大部分：

```
DSH.app/helpers/insert_dylib                       ✓ 已找到
Rein/tools/theos-root/usr/bin/install_name_tool    ✓ 已找到
DSH.app/helpers/ldid                               ✓ 已找到
Rein/tools/theos-root/usr/bin/chown                ✓ 已找到
ct_bypass                                          ✗ 需要自备
```

所以**注入链路在 Rein 环境里是现成可用的**，唯一缺口是 CoreTrust 绕过。

## 两种使用方式

### A. 设备内注入（App 的「注入」标签）

1. 选目标 App（自动枚举 `/private/var/containers/Bundle/Application`、`/Applications`、`/var/jb/Applications`）
2. 添加插件：dylib / framework / bundle / `.deb` / `.zip` 都行
3. 「预览注入计划」→ 看到每一步要做的事（先看清楚再动手）
4. 「开始注入」→ 自动备份 `.sparkbak`，逐步执行，日志落盘

### B. 离线注入（在电脑上给别人的 ipa 打补丁）

```bash
# 1. 解包
unzip App.ipa -d work

# 2. 生成计划（只打印，不动手）
node -e '
import("./ProjectKit/src/trollinject.mjs").then(m=>{
  const plan = m.planInjection({
    appPath: "work/Payload/App.app",
    executableName: "App",
    plugins: ["AdBlock.dylib"],
    options: { weak: true, coreTrustBypass: true },
  });
  console.log(plan.steps.map((s,i)=>`${i+1}. ${s.title}: ${s.detail}`).join("\n"));
})'

# 3. 真注入（设备上的工具或 macOS 上的 llvm-install-name-tool + ldid）
sh <(node -e '...injectionScript(plan)...')

# 4. 重新打包
cd work && zip -qry ../App-injected.ipa Payload
```

## 注意事项

- **注入会改坏原 App**：脚本第一步就是 `cp -R App.app App.app.sparkbak`，出问题把
  `.sparkbak` 改名回去即可。
- **没装 TrollStore 的机器**：注入后的 App 只能用「越狱环境 + ldid 签名」运行，
  不能直接点开 —— CoreTrust 绕过就是为这个场景准备的。
- **加密的 App Store 应用**：只能注入「裸 dylib」，且必须 `--weak`，否则 dyld 会因为
  找不到符号而崩（TrollFools 的 README 里也写了这条限制）。
- **不要注入系统 App**：`/Applications` 下的有些包带 SIP 保护，改了会开不了机。
