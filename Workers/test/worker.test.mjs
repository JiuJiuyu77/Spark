/**
 * Worker 的本地冒烟测试：不联网，用内存版 KV / R2 / fetch 桩跑一遍全流程。
 * 运行：node --test Workers/test/worker.test.mjs
 */
import test from 'node:test';
import assert from 'node:assert/strict';

import worker from '../SPCloudWorker.js';

/** 极简 KV */
function makeKV() {
  const m = new Map();
  return {
    async get(k) { return m.has(k) ? m.get(k) : null; },
    async put(k, v) { m.set(k, v); },
    async delete(k) { m.delete(k); },
    async list({ prefix = '' } = {}) {
      return { keys: [...m.keys()].filter((k) => k.startsWith(prefix)).map((name) => ({ name })) };
    },
    _map: m,
  };
}

/** 极简 R2 */
function makeR2() {
  const m = new Map();
  return {
    async put(k, body, opts) { m.set(k, { body, opts }); return { key: k }; },
    async get(k) { return m.get(k) || null; },
    async delete(k) { m.delete(k); },
    _map: m,
  };
}

function makeEnv(overrides = {}) {
  return {
    TOKEN: 'test-token-1234567890',
    GH_TOKEN: 'fake-gh',
    GH_OWNER: 'JiuJiuyu77',
    GH_REPO: 'Workbench',
    GH_WORKFLOW: 'build.yml',
    GH_REF: 'main',
    MAX_UPLOAD_MB: '1',
    JOBS: makeKV(),
    UPLOADS: makeR2(),
    ...overrides,
  };
}

const auth = { authorization: 'Bearer test-token-1234567890' };

test('健康检查不需要鉴权', async () => {
  const env = makeEnv();
  const res = await worker.fetch(new Request('https://x/health'), env);
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.ok, true);
  assert.ok(body.caps.includes('dispatch'));
});

test('缺少 token 返回 401', async () => {
  const env = makeEnv();
  const res = await worker.fetch(new Request('https://x/jobs'), env);
  assert.equal(res.status, 401);
});

test('错误 token 返回 401', async () => {
  const env = makeEnv();
  const res = await worker.fetch(new Request('https://x/jobs', { headers: { authorization: 'Bearer nope' } }), env);
  assert.equal(res.status, 401);
});

test('上传 zip 写入 R2 并记录任务', async () => {
  const env = makeEnv();
  const res = await worker.fetch(
    new Request('https://x/upload?job=rb_test1', { method: 'PUT', headers: auth, body: new Uint8Array([1, 2, 3]) }),
    env,
  );
  const body = await res.json();
  assert.equal(body.ok, true);
  assert.equal(body.job, 'rb_test1');
  assert.ok(env.UPLOADS._map.has('projects/rb_test1.zip'));
  assert.ok(env.JOBS._map.has('job:rb_test1'));
});

test('上传超过限额返回 413', async () => {
  const env = makeEnv({ MAX_UPLOAD_MB: '1' });
  const body = new Uint8Array(2 * 1024 * 1024);
  const res = await worker.fetch(
    new Request('https://x/upload?job=big', {
      method: 'PUT',
      headers: { ...auth, 'content-length': String(body.length) },
      body,
    }),
    env,
  );
  assert.equal(res.status, 413);
});

test('未知任务返回 404', async () => {
  const env = makeEnv();
  const res = await worker.fetch(new Request('https://x/status?job=nope', { headers: auth }), env);
  assert.equal(res.status, 404);
});

test('dispatch 会调用 GitHub workflow_dispatch', async () => {
  const env = makeEnv();
  const calls = [];
  globalThis.fetch = async (url, init) => {
    calls.push({ url: String(url), init });
    if (String(url).includes('/actions/workflows/')) return new Response(null, { status: 204 });
    return new Response('[]', { status: 200 });
  };
  const res = await worker.fetch(
    new Request('https://x/dispatch', {
      method: 'POST',
      headers: auth,
      body: JSON.stringify({ job: 'rb_d1', project: { name: 'Demo' }, options: { debug: true } }),
    }),
    env,
  );
  const body = await res.json();
  assert.equal(body.ok, true);
  assert.equal(body.state, 'dispatched');
  const dispatchCall = calls.find((c) => c.url.includes('/dispatches'));
  assert.ok(dispatchCall, '应该请求 dispatches 接口');
  const sent = JSON.parse(dispatchCall.init.body);
  assert.equal(sent.ref, 'main');
  assert.equal(sent.inputs.job_id, 'rb_d1');
});

test('jobs 列表按时间倒序', async () => {
  const env = makeEnv();
  env.JOBS._map.set('job:a', JSON.stringify({ id: 'a', createdAt: '2026-01-01T00:00:00Z' }));
  env.JOBS._map.set('job:b', JSON.stringify({ id: 'b', createdAt: '2026-02-01T00:00:00Z' }));
  const res = await worker.fetch(new Request('https://x/jobs', { headers: auth }), env);
  const body = await res.json();
  assert.equal(body.count, 2);
  assert.equal(body.jobs[0].id, 'b');
});

test('取消任务会删记录', async () => {
  const env = makeEnv();
  env.JOBS._map.set('job:c', JSON.stringify({ id: 'c', createdAt: '2026-01-01T00:00:00Z' }));
  globalThis.fetch = async () => new Response('{}', { status: 200 });
  const res = await worker.fetch(new Request('https://x/jobs/c', { method: 'DELETE', headers: auth }), env);
  const body = await res.json();
  assert.equal(body.ok, true);
  assert.equal(env.JOBS._map.has('job:c'), false);
});
