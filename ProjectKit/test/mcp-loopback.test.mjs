/**
 * MCP 只允许绑定回环地址 —— 这条是安全约束，必须有测试守着。
 * 一旦有人把它改成 0.0.0.0，这个测试会立刻失败。
 */
import test from 'node:test';
import assert from 'node:assert/strict';

import { assertLoopback, HTTP_BIND_HOST, startHttpServer } from '../../bin/spark-mcp.mjs';

test('默认绑定地址就是 127.0.0.1', () => {
  assert.equal(HTTP_BIND_HOST, '127.0.0.1');
});

test('回环地址全部放行', () => {
  for (const host of ['127.0.0.1', '::1', 'localhost', undefined]) {
    const r = assertLoopback(host);
    assert.equal(r.ok, true, `${host} 应该被允许`);
  }
});

test('非回环地址一律拒绝', () => {
  const banned = ['0.0.0.0', '::', '192.168.1.10', '10.0.0.2', 'example.com', '169.254.1.1'];
  for (const host of banned) {
    const r = assertLoopback(host);
    assert.equal(r.ok, false, `${host} 必须被拒绝`);
    assert.ok(r.reason.includes('127.0.0.1'), `${host} 的拒绝理由要提示回环地址`);
  }
});

test('startHttpServer 收到非法地址直接抛错，且不监听', async () => {
  await assert.rejects(
    () => startHttpServer({ host: '0.0.0.0', port: 17999 }),
    (err) => {
      assert.ok(err.message.includes('只允许绑定回环地址'));
      return true;
    },
  );
});

test('真启动时实际监听在 127.0.0.1 上', async () => {
  const server = await startHttpServer({ port: 17998 });
  try {
    const addr = server.address();
    assert.equal(addr.address, '127.0.0.1');
    assert.equal(addr.port, 17998);
  } finally {
    await new Promise((r) => server.close(r));
  }
});

test('HTTP 服务能用 JSON-RPC 完成一次 tools/list', async () => {
  const server = await startHttpServer({ port: 17997 });
  try {
    const res = await fetch('http://127.0.0.1:17997/mcp', {
      method: 'POST',
      body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'tools/list' }),
    });
    const data = await res.json();
    assert.ok(Array.isArray(data.result.tools));
    assert.ok(data.result.tools.some((t) => t.name === 'spark_doctor'));
  } finally {
    await new Promise((r) => server.close(r));
  }
});

test('/health 明确写出「仅本机可访问」', async () => {
  const server = await startHttpServer({ port: 17996 });
  try {
    const data = await fetch('http://127.0.0.1:17996/health').then((r) => r.json());
    assert.equal(data.bind.startsWith('127.0.0.1:'), true);
    assert.ok(data.note.includes('仅本机'));
  } finally {
    await new Promise((r) => server.close(r));
  }
});
