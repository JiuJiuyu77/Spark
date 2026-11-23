# MCP 支持（仅本地 127.0.0.1）

Workbench 内置一个 **MCP（Model Context Protocol）服务器**，让 Claude Desktop、Cursor、
Zed 或你自己写的 agent 直接调用 Workbench 的编译/注入/逆向能力。

> ⚠️ **安全边界：只监听 127.0.0.1。**
> Workbench 能读写整个文件系统、能起编译进程。一旦监听 `0.0.0.0`，同一 WiFi 下任何人
> 都能借它执行命令。所以监听地址在代码里写死为回环地址，不提供配置项：

```js
export const HTTP_BIND_HOST = '127.0.0.1';   // 刻意不可配置
```

`startHttpServer({ host: '0.0.0.0' })` 会直接抛错；`assertLoopback()` 会拒绝
`0.0.0.0 / :: / 192.168.* / 10.*` 等一切非回环地址，并且有单元测试守着
（`ProjectKit/test/mcp-loopback.test.mjs`）。

## 两种传输

| 传输 | 命令 | 适用 |
|---|---|---|
| **stdio**（默认） | `node bin/spark-mcp.mjs` | Claude Desktop / Cursor / Zed 等桌面 MCP 客户端 |
| **HTTP** | `node bin/spark-mcp.mjs --http` | 浏览器里的 MCP 客户端、自己写的小工具（http://127.0.0.1:7878/mcp） |

## 提供的工具

| 工具 | 作用 |
|---|---|
| `spark_doctor` | 探测 Theos / SDK / OLLVM / 逆向工具 / 注入工具链是否齐备，缺什么、怎么补 |
| `spark_projects` | 扫描目录，识别 tweak / application / library / tool / node 项目 |
| `spark_read_file` | 读文本文件（默认 400 行上限，避免撑爆上下文） |
| `spark_build_script` | 生成完整的 Theos 构建脚本（含工具链自检、OLLVM flags、产物收集） |
| `spark_inject_plan` | 生成巨魔注入计划（含可执行脚本，见 [troll-inject.md](troll-inject.md)） |
| `spark_analyze` | 调 radare2 做 Mach-O 分析（架构 / 符号 / 字符串 / 依赖 / 段） |

## Claude Desktop 配置

`~/Library/Application Support/Claude/claude_desktop_config.json`：

```json
{
  "mcpServers": {
    "spark": {
      "command": "node",
      "args": ["/var/mobile/Documents/Workbench/bin/spark-mcp.mjs"],
      "env": {
        "SPARK_REIN_ROOT": "/var/mobile/Documents/Rein",
        "SPARK_APP_PATH": "/Applications/Workbench.app"
      }
    }
  }
}
```

- `SPARK_REIN_ROOT`：Rein 数据目录（找 Theos / SDK / OLLVM）
- `SPARK_APP_PATH`：Workbench.app 路径（工具探测会顺带看它的 `helpers/`，
  Rein 里那套裁过的 `insert_dylib` / `ldid` 就在那儿）

## 手测（不装客户端也能验）

```bash
# stdio：直接喂 JSON-RPC
printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
  '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"spark_doctor","arguments":{}}}' \
  | node bin/spark-mcp.mjs
```

```bash
# HTTP：只在本机可用
node bin/spark-mcp.mjs --http --port 7878 &
curl -s http://127.0.0.1:7878/health
curl -s -X POST http://127.0.0.1:7878/mcp \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"spark_doctor","arguments":{}}}'
```

## 远程怎么用

不要改监听地址。正确做法是 SSH 隧道，把远端端口映射到本机回环：

```bash
ssh -L 7878:127.0.0.1:7878 root@你的设备IP
# 然后本地访问 http://127.0.0.1:7878/mcp 即可
```

隧道两端都在回环上，端口不对外暴露；即使有人扫你的局域网也连不上。

## 协议细节

- 协议版本：`2024-11-05`
- 支持方法：`initialize`、`ping`、`tools/list`、`tools/call`、
  `resources/list`、`resources/read`、`notifications/*`（忽略）
- stdio 用换行分隔 JSON；HTTP 用 POST `/mcp`，批量请求支持 JSON 数组
- 未实现的方法返回 `-32601`，参数错误 `-32602`，解析失败 `-32700`

## 为什么只做 6 个工具

MCP 的价值是「让模型做它能做好的事」。编译本身要几分钟、要占 CPU，
不适合塞进一次 tool call —— 所以 `spark_build_script` 只**生成脚本**，
真正的执行交给人（App 里点按钮，或终端里跑）。模型负责判断「该用什么参数、
为什么失败」，机器负责跑。
