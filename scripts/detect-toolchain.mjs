#!/usr/bin/env node
/**
 * Workbench 工具链探测 —— 纯 Node，无第三方依赖。
 *
 * 用途：
 *   1. 在命令行快速看清本机 Rein 环境到底有哪些编译能力
 *   2. 输出 JSON 给 CI / 外部脚本用
 *
 * 用法：
 *   node scripts/detect-toolchain.mjs             # 人类可读
 *   node scripts/detect-toolchain.mjs --json      # 机器可读
 *   REIN_ROOT=/path node scripts/detect-toolchain.mjs
 */
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';

const AS_JSON = process.argv.includes('--json');
const HOME = process.env.HOME || os.homedir();
const ROOTS = [
  process.env.REIN_ROOT,
  path.join(HOME, 'Documents', 'Rein'),
  '/var/mobile/Documents/Rein',
  path.join(HOME, 'Rein'),
].filter(Boolean);

const ok = (p) => p && fs.existsSync(p);
const isDir = (p) => ok(p) && fs.statSync(p).isDirectory();
const isExec = (p) => {
  if (!ok(p)) return false;
  try {
    fs.accessSync(p, fs.constants.X_OK);
    return true;
  } catch {
    return false;
  }
};

function firstDir(list) {
  return list.find((p) => isDir(p)) || null;
}

function firstExec(list) {
  return list.find((p) => isExec(p)) || null;
}

function sdksIn(dir) {
  if (!isDir(dir)) return [];
  return fs
    .readdirSync(dir)
    .filter((n) => n.endsWith('.sdk') && n.startsWith('iPhoneOS'))
    .sort();
}

function detect(root) {
  const r = (p) => path.join(root, p);
  const result = { root, components: {}, sdks: [], ollvmPasses: [], reverseTools: [] };

  // Theos
  const theos = firstDir([r('tools/theos-full'), r('tools/theos-local'), r('theos-root/theos'), r('theos')]);
  result.components.theos = {
    ok: !!theos,
    path: theos,
    bins: theos ? ['bin/logos.pl', 'bin/nic.pl', 'bin/dm.pl', 'bin/fakeroot.sh'].map((b) => ({ name: b, ok: isExec(path.join(theos, b)) })) : [],
  };

  // SDKs
  for (const d of [theos && path.join(theos, 'sdks'), r('sdks-store'), r('sdks')]) {
    for (const s of sdksIn(d)) {
      const p = path.join(d, s);
      if (!result.sdks.find((x) => x.name === s)) result.sdks.push({ name: s, path: p });
    }
  }
  result.components.sdk = { ok: result.sdks.length > 0, count: result.sdks.length };

  // Darwin 工具（真机可执行）
  const darwin = firstDir([r('tools/theos-root/usr/bin')]);
  const darwinTools = ['clang-16', 'ld64', 'ldid', 'strip', 'ar'];
  result.components.darwin = {
    ok: !!darwin && darwinTools.some((t) => ok(path.join(darwin, t))),
    path: darwin,
    tools: darwin ? darwinTools.map((t) => ({ name: t, ok: ok(path.join(darwin, t)) })) : [],
  };

  // OLLVM
  const ollvm = firstDir([r('tools/ollvm'), r('ollvm')]);
  const manifest = ollvm && ok(path.join(ollvm, 'manifest.json'))
    ? JSON.parse(fs.readFileSync(path.join(ollvm, 'manifest.json'), 'utf8'))
    : null;
  result.components.ollvm = {
    ok: !!ollvm && ok(path.join(ollvm, 'bin/clang')),
    path: ollvm,
    llvm: manifest ? manifest.llvm_version : null,
    name: manifest ? manifest.name : null,
  };
  if (manifest && Array.isArray(manifest.passes)) {
    result.ollvmPasses = manifest.passes.map((p) => ({ id: p.id, title: p.title, flags: p.flags }));
  }

  // 逆向
  const rev = firstDir([r('tools/reverse/bin')]);
  const revTools = ['radare2', 'rabin2', 'rasm2', 'radiff2', 'rahash2', 'mt-macho', 'mt-inject-dylib', 'mt-rev'];
  result.components.reverse = {
    ok: !!rev && revTools.some((t) => ok(path.join(rev, t))),
    path: rev,
    tools: rev ? revTools.map((t) => ({ name: t, ok: ok(path.join(rev, t)) })) : [],
  };
  if (rev) result.reverseTools = revTools.filter((t) => ok(path.join(rev, t)));

  // 其它
  result.components.python = { ok: !!firstExec([r('tools/python/python3'), r('tools/python/python'), r('bin/python3')]) };
  result.components.node = { ok: !!firstExec([r('bin/node22'), r('bin/node'), r('helpers/node')]) };
  result.components.pnpm = { ok: !!firstExec([r('bin/pnpm'), r('tools/pnpm/bin/pnpm.cjs')]) };
  result.components.helpers = {
    ok: isDir(r('helpers')) || isDir(r('tools/bin')),
    path: firstDir([r('tools/bin')]),
  };

  return result;
}

const marks = { true: '\x1b[32m✓\x1b[0m', false: '\x1b[31m✗\x1b[0m' };

function report(results, found) {
  const best = results[0];
  if (!best) {
    console.log('没有找到任何 Rein 目录。用 REIN_ROOT=... 指定。');
    process.exit(1);
  }
  console.log(`\nWorkbench 工具链探测\n扫描目录：${(found || results.map((r) => r.root)).join("\n          ")}\n`);
  const labels = {
    theos: 'Theos',
    sdk: 'iPhoneOS SDK',
    darwin: 'Darwin 工具（真机编译）',
    ollvm: 'OLLVM 混淆',
    reverse: '逆向工具',
    python: 'Python',
    node: 'Node',
    pnpm: 'pnpm',
    helpers: 'Theos 辅助脚本',
  };
  for (const [k, label] of Object.entries(labels)) {
    const c = best.components[k];
    console.log(`${marks[!!c.ok]} ${label.padEnd(22)} ${c.path || ''}`);
    if (c.ok && c.tools) {
      console.log(`    ${c.tools.map((t) => `${t.ok ? '·' : '✗'}${t.name}`).join('  ')}`);
    }
    if (k === 'ollvm' && c.llvm) console.log(`    ${c.name}（LLVM ${c.llvm}）`);
  }
  if (best.sdks.length) {
    console.log(`\n可用 SDK：`);
    for (const s of best.sdks) console.log(`  · ${s.name}   ${s.path}`);
  }
  if (best.ollvmPasses.length) {
    console.log(`\nOLLVM passes：`);
    for (const p of best.ollvmPasses) console.log(`  · ${p.id.padEnd(6)} ${p.title.padEnd(26)} ${p.flags.join(' ')}`);
  }
  console.log('');
}

const results = ROOTS.map((root) => ({ root, exists: isDir(root) }))
  .filter((x) => x.exists)
  .map((x) => detect(x.root));

if (AS_JSON) {
  console.log(JSON.stringify(results, null, 2));
} else {
  report(results);
}
