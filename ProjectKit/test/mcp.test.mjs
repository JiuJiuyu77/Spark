import test from 'node:test';
import assert from 'node:assert/strict';

import {
  callTool,
  TOOL_DEFINITIONS,
  MCP_PROTOCOL_VERSION,
  describeCapabilities,
} from '../src/mcp-tools.mjs';

/** 一个假文件系统：路径 → 内容（目录用 null 表示） */
const FAKE_FS = {
  '/root': null,
  '/root/MyTweak': null,
  '/root/MyTweak/Makefile': 'TWEAK_NAME = MyTweak\nMyTweak_FILES = Tweak.x\n',
  '/root/MyTweak/control': 'Package: com.example.mytweak\nVersion: 2.1.0\n',
  '/root/Plain': null,
  '/root/Plain/readme.txt': 'hello',
  '/re': null,
  '/re/ollvm/bin/clang': 'bin',
  '/re/tools/ollvm/bin/clang': 'bin',
  '/re/tools/theos-full': null,
  '/re/tools/theos-full/bin/logos.pl': 'perl',
  '/re/sdks-store': null,
  '/re/sdks-store/iPhoneOS16.5.sdk': null,
  '/re/sdks-store/iPhoneOS17.0.sdk': null,
};

function deps(extra = {}) {
  return {
    env: { REIN_ROOT: '/re' },
    exists: (p) => Object.prototype.hasOwnProperty.call(FAKE_FS, p),
    readdir: (p) => {
      const prefix = p.endsWith('/') ? p : p + '/';
      const kids = new Set();
      for (const k of Object.keys(FAKE_FS)) {
        if (k.startsWith(prefix)) {
          const rest = k.slice(prefix.length).split('/')[0];
          if (rest) kids.add(rest);
        }
      }
      return [...kids];
    },
    readFile: (p) => (typeof FAKE_FS[p] === 'string' ? FAKE_FS[p] : ''),
    pathJoin: (...parts) => parts.join('/').replace(/\/+/g, '/'),
    run: async () => ({ code: 0, stdout: 'arch     arm64\n', stderr: '' }),
    ...extra,
  };
}

test('工具清单齐全且都有 schema', () => {
  const names = TOOL_DEFINITIONS.map((t) => t.name);
  assert.deepEqual(names, [
    'spark_doctor',
    'spark_projects',
    'spark_read_file',
    'spark_build_script',
    'spark_inject_plan',
    'spark_analyze',
  ]);
  for (const t of TOOL_DEFINITIONS) {
    assert.equal(t.inputSchema.type, 'object');
    assert.ok(t.description.length > 10);
  }
  assert.equal(MCP_PROTOCOL_VERSION, '2024-11-05');
});

test('spark_doctor 报出 SDK 与 Theos', async () => {
  const r = await callTool('spark_doctor', { reinRoot: '/re' }, deps());
  const text = r.content[0].text;
  assert.ok(text.includes('iPhoneOS17.0.sdk'));
  assert.ok(text.includes('Theos(Logos): 可用'));
  assert.ok(text.includes('OLLVM clang: 可用'));
});

test('spark_projects 能识别 tweak', async () => {
  const r = await callTool('spark_projects', { root: '/root' }, deps());
  const text = r.content[0].text;
  assert.ok(text.includes('MyTweak'));
  assert.ok(text.includes('[tweak]'));
  assert.ok(text.includes('com.example.mytweak'));
});

test('spark_projects 目录不存在时报错', async () => {
  const r = await callTool('spark_projects', { root: '/nope' }, deps());
  assert.equal(r.isError, true);
  assert.ok(r.content[0].text.includes('不存在'));
});

test('spark_read_file 会截断', async () => {
  const many = Array.from({ length: 50 }, (_, i) => `line ${i}`).join('\n');
  const r = await callTool('spark_read_file', { path: '/a.txt', maxLines: 10 }, deps({
    exists: () => true,
    readFile: () => many,
  }));
  const text = r.content[0].text;
  assert.ok(text.includes('line 0'));
  assert.ok(!text.includes('line 20'));
  assert.ok(text.includes('已截断'));
});

test('spark_build_script 生成合法脚本', async () => {
  const r = await callTool(
    'spark_build_script',
    { path: '/root/MyTweak', obfuscation: 'balanced', arch: 'arm64e' },
    deps(),
  );
  const text = r.content[0].text;
  assert.ok(text.includes('#!/bin/sh'));
  assert.ok(text.includes('make package'));
  assert.ok(text.includes('--irobf-icall'));
  assert.ok(text.includes('ARCHS=arm64e'));
  assert.ok(text.includes('set -o pipefail'));
});

test('spark_build_script 对非 Theos 项目报错', async () => {
  const r = await callTool('spark_build_script', { path: '/root/Plain' }, deps());
  assert.equal(r.isError, true);
  assert.ok(r.content[0].text.includes('不是 Theos 项目'));
});

test('spark_inject_plan 给出步骤，可选带脚本', async () => {
  const r = await callTool(
    'spark_inject_plan',
    { appPath: '/Applications/Demo.app', plugins: ['/tmp/AdBlock.dylib'], script: true },
    deps(),
  );
  const text = r.content[0].text;
  assert.ok(text.includes('备份'));
  assert.ok(text.includes('CydiaSubstrate'));
  assert.ok(text.includes('insert_dylib'));
  assert.ok(text.includes('```sh'));
  assert.ok(text.includes('@executable_path/AdBlock.dylib'));
});

test('spark_inject_plan 缺插件时报错', async () => {
  const r = await callTool('spark_inject_plan', { appPath: '/A.app', plugins: [] }, deps());
  assert.equal(r.isError, true);
});

test('spark_analyze 走 run 依赖', async () => {
  let called = null;
  const r = await callTool('spark_analyze', { path: '/bin/x', mode: 'symbols' }, deps({
    exists: () => true,
    run: async (cmd, args) => {
      called = { cmd, args };
      return { code: 0, stdout: 'sym1\nsym2\n', stderr: '' };
    },
  }));
  assert.equal(called.cmd, 'rabin2');
  assert.deepEqual(called.args, ['-s', '/bin/x']);
  assert.ok(r.content[0].text.includes('sym1'));
});

test('spark_analyze 工具缺失时给出提示', async () => {
  const r = await callTool('spark_analyze', { path: '/bin/x' }, deps({
    exists: () => true,
    run: async () => ({ code: 127, stdout: '', stderr: 'not found' }),
  }));
  assert.equal(r.isError, true);
  assert.ok(r.content[0].text.includes('tools/reverse/bin/rabin2'));
});

test('未知工具返回错误', async () => {
  const r = await callTool('spark_nope', {}, deps());
  assert.equal(r.isError, true);
});

test('能力说明包含 pass 与预设', () => {
  const text = describeCapabilities();
  assert.ok(text.includes('indbr'));
  assert.ok(text.includes('balanced'));
  assert.ok(text.includes('spark_build_script'));
});
