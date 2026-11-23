#!/usr/bin/env node
/**
 * spark-mcp —— 把 Workbench 包成 MCP 服务器
 *
 * 传输：
 *   stdio（默认，MCP 标准；Claude Desktop / Cursor / Zed 都支持）
 *     node bin/spark-mcp.mjs
 *   HTTP（给浏览器/网页版 MCP 客户端用）
 *     node bin/spark-mcp.mjs --http
 *
 * ⚠️ HTTP 传输**只监听 127.0.0.1（回环）**，不接受局域网/公网连接。
 *    这是硬约束：Workbench 能读写整个文件系统、能起编译进程，
 *    一旦暴露到 0.0.0.0，同一网络里任何人都能借它执行命令。
 *    想远程用请走 SSH 隧道：ssh -L 7878:127.0.0.1:7878 你的设备
 *
 * Claude Desktop 配置示例（claude_desktop_config.json）：
 *   {
 *     "mcpServers": {
 *       "spark": {
 *         "command": "node",
 *         "args": ["/path/to/Workbench/bin/spark-mcp.mjs"],
 *         "env": { "SPARK_REIN_ROOT": "/var/mobile/Documents/Rein" }
 *       }
 *     }
 *   }
 *
 * 协议实现要点（无 SDK 依赖，手写最小可用集）：
 *   initialize → tools/list → tools/call
 *   resources/list → resources/read（能力说明）
 *   ping / notifications/*（直接忽略通知）
 * 每条消息一行 JSON（stdio 用 \n 分隔，不用 LSP 的 Content-Length 头）。
 */
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { spawnSync } from 'node:child_process';
import { createInterface } from 'node:readline';

import {
  callTool,
  TOOL_DEFINITIONS,
  MCP_PROTOCOL_VERSION,
  SERVER_INFO,
  describeCapabilities,
} from '../ProjectKit/src/mcp-tools.mjs';

const REIN_ROOT = process.env.SPARK_REIN_ROOT || process.env.REIN_ROOT || path.join(os.homedir(), 'Documents/Rein');

/** 给 MCP 工具用的真实依赖实现 */
const deps = {
  env: { REIN_ROOT },
  exists: (p) => {
    try {
      fs.accessSync(p);
      return true;
    } catch {
      return false;
    }
  },
  readdir: (p) => {
    try {
      return fs.readdirSync(p);
    } catch {
      return [];
    }
  },
  readFile: (p) => {
    try {
      return fs.readFileSync(p, 'utf8');
    } catch {
      return '';
    }
  },
  pathJoin: (...parts) => path.join(...parts),
  /** 只在 callTool 需要时才会用到；这里同步跑，超时 30s */
  run: async (cmd, args) => {
    const candidates = [
      path.join(REIN_ROOT, 'tools/reverse/bin', cmd),
      path.join(REIN_ROOT, 'tools/theos-root/usr/bin', cmd),
      cmd,
    ];
    const exe = candidates.find((c) => c === cmd || deps.exists(c)) || cmd;
    const r = spawnSync(exe, args, { encoding: 'utf8', timeout: 30000 });
    return {
      code: r.status ?? (r.error ? 1 : 0),
      stdout: r.stdout || '',
      stderr: r.stderr || (r.error ? String(r.error.message) : ''),
    };
  },
};

const send = (msg) => {
  process.stdout.write(JSON.stringify(msg) + '\n');
};

const ok = (id, result) => send({ jsonrpc: '2.0', id, result });
const fail = (id, code, message) => send({ jsonrpc: '2.0', id, error: { code, message } });

async function handle(msg) {
  const { id, method, params } = msg;
  // 通知类消息不回包
  if (method && method.startsWith('notifications/')) return;

  switch (method) {
    case 'initialize':
      return ok(id, {
        protocolVersion: MCP_PROTOCOL_VERSION,
        capabilities: {
          tools: { listChanged: false },
          resources: { subscribe: false, listChanged: false },
        },
        serverInfo: SERVER_INFO,
        instructions:
          'Workbench 是一个 iOS 编译工具：可以探测 Theos/OLLVM/逆向工具链、生成 Theos 构建脚本、' +
          '生成巨魔（TrollStore）注入计划、分析 Mach-O。优先用 spark_doctor 看环境，' +
          '再用 spark_projects 找项目，最后用 spark_build_script 拿构建脚本。',
      });

    case 'ping':
      return ok(id, {});

    case 'tools/list':
      return ok(id, { tools: TOOL_DEFINITIONS });

    case 'tools/call': {
      const name = params?.name;
      const args = params?.arguments || {};
      if (!TOOL_DEFINITIONS.some((t) => t.name === name)) {
        return fail(id, -32602, `未知工具：${name}`);
      }
      const result = await callTool(name, args, deps);
      return ok(id, result);
    }

    case 'resources/list':
      return ok(id, {
        resources: [
          {
            uri: 'spark://capabilities',
            name: 'Workbench 能力说明',
            description: '工具清单、OLLVM pass 与混淆预设',
            mimeType: 'text/markdown',
          },
        ],
      });

    case 'resources/read':
      return ok(id, {
        contents: [
          {
            uri: params?.uri || 'spark://capabilities',
            mimeType: 'text/markdown',
            text: describeCapabilities(),
          },
        ],
      });

    default:
      if (id === undefined || id === null) return;
      return fail(id, -32601, `不支持的方法：${method}`);
  }
}

export function startServer(input = process.stdin, output = process.stdout) {
  const rl = createInterface({ input, crlfDelay: Infinity });
  rl.on('line', (line) => {
    const text = line.trim();
    if (!text) return;
    let msg;
    try {
      msg = JSON.parse(text);
    } catch {
      output.write(JSON.stringify({ jsonrpc: '2.0', id: null, error: { code: -32700, message: '解析失败' } }) + '\n');
      return;
    }
    Promise.resolve(handle(msg)).catch((e) => {
      if (msg && msg.id !== undefined) fail(msg.id, -32603, String(e && e.message ? e.message : e));
    });
  });
  return rl;
}

// 只有直接运行才启服务，被 import 时（测试）不启动
if (process.argv[1] && import.meta.url.endsWith(path.basename(process.argv[1]))) {
  const verbose = process.argv.includes('--verbose');
  if (verbose) process.stderr.write(`[spark-mcp] reinRoot=${REIN_ROOT}\n`);

  if (process.argv.includes('--http')) {
    const portArg = process.argv.indexOf('--port');
    const port = portArg > 0 ? Number(process.argv[portArg + 1]) : HTTP_DEFAULT_PORT;
    // 注意：这里没有 --host 参数，地址永远是 127.0.0.1
    if (process.argv.includes('--host')) {
      process.stderr.write('[spark-mcp] 忽略 --host：只允许绑定 127.0.0.1\n');
    }
    startHttpServer({ port })
      .then(() => {
        process.stderr.write(`[spark-mcp] HTTP server ready at http://127.0.0.1:${port}/mcp （仅本机可访问）\n`);
      })
      .catch((e) => {
        process.stderr.write(`[spark-mcp] 启动失败：${e.message}\n`);
        process.exit(1);
      });
  } else {
    startServer();
    process.stderr.write('[spark-mcp] stdio server ready\n');
  }
}


// ---------------------------------------------------------------------------
// HTTP 传输：只为「本地网页版 MCP 客户端」准备，绑定地址写死 127.0.0.1
// ---------------------------------------------------------------------------

export const HTTP_DEFAULT_PORT = 7878;
/** 唯一允许的监听地址 —— 刻意不做成可配置，避免有人手滑改成 0.0.0.0 */
export const HTTP_BIND_HOST = '127.0.0.1';

/**
 * 校验监听地址：任何非回环地址都会被拒绝。
 * @returns {{ok: boolean, host: string, reason?: string}}
 */
export function assertLoopback(host) {
  const allowed = new Set(['127.0.0.1', '::1', 'localhost']);
  if (!host) return { ok: true, host: HTTP_BIND_HOST };
  if (!allowed.has(host)) {
    return {
      ok: false,
      host,
      reason: `拒绝监听 ${host}：Workbench MCP 只允许绑定回环地址（127.0.0.1 / ::1）。` +
        '需要远程访问请用 SSH 隧道，不要直接暴露端口。',
    };
  }
  return { ok: true, host };
}

/**
 * 启动 HTTP 服务。返回的 server 需要在调用方负责 close。
 * 用 Node 内置 http 模块，不引第三方依赖（设备上的 node22 也够用）。
 */
export async function startHttpServer({ host = HTTP_BIND_HOST, port = HTTP_DEFAULT_PORT } = {}) {
  const check = assertLoopback(host);
  if (!check.ok) throw new Error(check.reason);

  const { createServer } = await import('node:http');

  const server = createServer(async (req, res) => {
    const sendJson = (obj, status = 200) => {
      const payload = JSON.stringify(obj);
      res.writeHead(status, {
        'content-type': 'application/json; charset=utf-8',
        'cache-control': 'no-store',
        'content-length': Buffer.byteLength(payload),
      });
      res.end(payload);
    };

    // 额外的兜底防线：如果请求不是从回环地址发来的（比如通过某种转发），直接拒
    const remote = req.socket.remoteAddress || '';
    const isLocal = remote === '127.0.0.1' || remote === '::1' || remote === '::ffff:127.0.0.1';
    if (!isLocal) {
      return sendJson({ jsonrpc: '2.0', id: null, error: { code: -32000, message: '仅允许本机访问' } }, 403);
    }

    if (req.method === 'GET' && (req.url === '/' || req.url === '/health')) {
      return sendJson({
        ok: true,
        service: 'spark-mcp',
        transport: 'http',
        bind: `${HTTP_BIND_HOST}:${port}`,
        note: '仅本机可访问',
      });
    }
    if (req.method === 'GET' && req.url === '/mcp') {
      // 人肉调试：把能力说明直接吐出来
      res.writeHead(200, { 'content-type': 'text/markdown; charset=utf-8', 'cache-control': 'no-store' });
      return res.end(describeCapabilities());
    }
    if (req.method !== 'POST' || req.url !== '/mcp') {
      return sendJson({ jsonrpc: '2.0', id: null, error: { code: -32601, message: 'unsupported' } }, 404);
    }

    let raw = '';
    for await (const chunk of req) raw += chunk;
    let msg;
    try {
      msg = JSON.parse(raw);
    } catch {
      return sendJson({ jsonrpc: '2.0', id: null, error: { code: -32700, message: '解析失败' } }, 400);
    }

    // stdio 版靠 output 写回，这里临时替换 send 的目标：直接拿到响应对象
    const response = await dispatch(msg);
    if (!response) return sendJson({ ok: true }, 202);
    return sendJson(response);
  });

  await new Promise((resolve, reject) => {
    server.once('error', reject);
    // host 传 127.0.0.1，绝不传 0.0.0.0
    server.listen(port, HTTP_BIND_HOST, () => resolve());
  });
  return server;
}

/** 抽出「处理单条 JSON-RPC 并返回响应对象」，stdio 与 http 共用 */
export async function dispatch(msg) {
  if (Array.isArray(msg)) {
    const out = [];
    for (const m of msg) {
      const r = await handleMessage(m);
      if (r) out.push(r);
    }
    return out;
  }
  return handleMessage(msg);
}

/** handle 的返回值版（标准 JSON-RPC 对象），供 HTTP 使用 */
async function handleMessage(msg) {
  const { id, method, params } = msg || {};
  if (method && method.startsWith('notifications/')) return null;

  switch (method) {
    case 'initialize':
      return rpcOkObj(id, {
        protocolVersion: MCP_PROTOCOL_VERSION,
        capabilities: { tools: { listChanged: false }, resources: { subscribe: false } },
        serverInfo: SERVER_INFO,
        instructions:
          'Workbench 是一个 iOS 编译工具：探测工具链、生成 Theos 构建脚本、生成巨魔注入计划、分析 Mach-O。',
      });
    case 'ping':
      return rpcOkObj(id, {});
    case 'tools/list':
      return rpcOkObj(id, { tools: TOOL_DEFINITIONS });
    case 'tools/call': {
      const name = params?.name;
      if (!TOOL_DEFINITIONS.some((t) => t.name === name)) {
        return { jsonrpc: '2.0', id: id ?? null, error: { code: -32602, message: `未知工具：${name}` } };
      }
      const result = await callTool(name, params?.arguments || {}, deps);
      return rpcOkObj(id, result);
    }
    case 'resources/list':
      return rpcOkObj(id, {
        resources: [{ uri: 'spark://capabilities', name: 'Workbench 能力说明', mimeType: 'text/markdown' }],
      });
    case 'resources/read':
      return rpcOkObj(id, {
        contents: [{ uri: params?.uri || 'spark://capabilities', mimeType: 'text/markdown', text: describeCapabilities() }],
      });
    default:
      if (id === undefined || id === null) return null;
      return { jsonrpc: '2.0', id, error: { code: -32601, message: `不支持的方法：${method}` } };
  }
}

const rpcOkObj = (id, result) => ({ jsonrpc: '2.0', id, result });
