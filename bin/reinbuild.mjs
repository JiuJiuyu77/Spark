#!/usr/bin/env node
/**
 * spark —— 命令行入口，配合 Workbench App 的「工具链」页使用。
 *
 * 用法：
 *   node bin/spark.mjs doctor                     # 体检：有哪些编译能力
 *   node bin/spark.mjs projects                   # 列出候选项目
 *   node bin/spark.mjs script <项目目录> [选项]    # 打印构建脚本
 *   node bin/spark.mjs build  <项目目录> [选项]    # 直接编译（真机编译）
 *   node bin/spark.mjs analyze <二进制> [模式]     # 逆向分析（rabin2）
 *
 * 选项：
 *   --ollvm none|light|balanced|strong|custom   --passes indbr,icall,...
 *   --arch arm64|arm64e|both                   --format deb|rootless|app
 *   --release  --clean  --jobs N  --sdk iPhoneOS17.0.sdk
 */
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { spawn } from 'node:child_process';

import { buildScript, defaultOptions, detectProject, diagnose, detectProject as _d } from '../ShareKit/src/model.js';

const HOME = process.env.HOME || os.homedir();
const REIN_ROOT = process.env.REIN_ROOT || path.join(HOME, 'Documents/Rein');

function flag(name, fallback = null) {
  const i = process.argv.indexOf(`--${name}`);
  if (i < 0) return fallback;
  const v = process.argv[i + 1];
  return v && !v.startsWith('--') ? v : true;
}

function exists(p) {
  try {
    fs.accessSync(p);
    return true;
  } catch {
    return false;
  }
}

function findFirst(list) {
  return list.find(exists) || null;
}

function toolchain() {
  const theos = findFirst([
    path.join(REIN_ROOT, 'tools/theos-full'),
    path.join(REIN_ROOT, 'tools/theos-local'),
    path.join(REIN_ROOT, 'theos-root/theos'),
    '/opt/theos',
  ]);
  let sdk = null;
  const wanted = flag('sdk');
  if (theos && exists(path.join(theos, 'sdks'))) {
    const names = fs
      .readdirSync(path.join(theos, 'sdks'))
      .filter((n) => n.startsWith('iPhoneOS') && n.endsWith('.sdk'))
      .sort();
    const picked = wanted && names.includes(wanted) ? wanted : names[names.length - 1];
    if (picked) sdk = path.join(theos, 'sdks', picked);
  }
  const ollvmRoot = findFirst([path.join(REIN_ROOT, 'tools/ollvm'), path.join(REIN_ROOT, 'ollvm')]);
  const reverseBin = findFirst([path.join(REIN_ROOT, 'tools/reverse/bin')]);
  return { theos, sdk, ollvmRoot, reverseBin };
}

function detectProjectAt(dir) {
  const io = {
    hasFile: (rel) => exists(path.join(dir, rel)),
    readFile: (rel) => {
      try {
        return fs.readFileSync(path.join(dir, rel), 'utf8');
      } catch {
        return null;
      }
    },
  };
  return detectProject(io);
}

function runShell(script, cwd) {
  return new Promise((resolve) => {
    const child = spawn('/bin/sh', ['-c', script], { cwd, stdio: 'inherit' });
    child.on('exit', (code, signal) => resolve({ code, signal }));
  });
}

function optionsFromFlags() {
  const o = defaultOptions();
  const arch = flag('arch');
  if (arch && arch !== true) o.arch = arch;
  const format = flag('format');
  if (format && format !== true) o.format = format;
  if (flag('release')) {
    o.debug = false;
    o.strip = true;
  }
  if (flag('clean')) o.clean = true;
  const ollvm = flag('ollvm');
  if (ollvm && ollvm !== true) {
    o.ollvm = ollvm !== 'none';
    o.obfuscation = ollvm;
  }
  const passes = flag('passes');
  if (passes && passes !== true) {
    o.passes = String(passes).split(',').map((s) => s.trim()).filter(Boolean);
    o.obfuscation = 'custom';
    o.ollvm = o.passes.length > 0;
  }
  const jobs = flag('jobs');
  if (jobs && jobs !== true) o.jobs = Number(jobs);
  return o;
}

async function cmdDoctor() {
  console.log('Workbench doctor\n');
  const tc = toolchain();
  const lines = [
    ['Rein 目录', REIN_ROOT],
    ['Theos', tc.theos],
    ['SDK', tc.sdk],
    ['OLLVM', tc.ollvmRoot],
    ['逆向工具', tc.reverseBin],
    ['make', findFirst(['/usr/bin/make', '/var/jb/usr/bin/make'])],
    ['ldid', findFirst([tc.theos ? path.join(tc.theos, 'bin/ldid') : '', '/usr/bin/ldid'])],
  ];
  for (const [name, value] of lines) {
    console.log(`${value ? '✓' : '✗'} ${name.padEnd(10)} ${value || '未找到'}`);
  }
  console.log('\n提示：运行 scripts/detect-toolchain.mjs 可以看到更完整的清单。');
}

async function cmdProjects() {
  const roots = [
    path.join(HOME, 'Documents/Workbench/projects'),
    path.join(REIN_ROOT, 'workspace'),
    path.join(REIN_ROOT, 'home'),
  ];
  for (const root of roots) {
    if (!exists(root)) continue;
    console.log(`\n${root}`);
    for (const name of fs.readdirSync(root)) {
      const dir = path.join(root, name);
      let isDir = false;
      try {
        isDir = fs.statSync(dir).isDirectory();
      } catch {
        /* 忽略 */
      }
      if (!isDir) continue;
      const info = detectProjectAt(dir);
      const mark = info.isTheos ? '●' : '○';
      console.log(`  ${mark} ${name.padEnd(32)} ${info.kind.padEnd(12)} ${info.packageId || ''}`);
    }
  }
}

async function cmdScript() {
  const target = process.argv[3];
  if (!target) return console.error('用法：spark script <项目目录>');
  const dir = path.resolve(target);
  const tc = toolchain();
  const script = buildScript({ path: dir }, optionsFromFlags(), tc);
  process.stdout.write(script);
}

async function cmdBuild() {
  const target = process.argv[3];
  if (!target) return console.error('用法：spark build <项目目录>');
  const dir = path.resolve(target);
  if (!exists(dir)) return console.error(`目录不存在：${dir}`);
  const tc = toolchain();
  const info = detectProjectAt(dir);
  console.log(`# 项目 ${info.kind}  ${info.packageId || ''}\n`);
  const script = buildScript({ path: dir }, optionsFromFlags(), tc);
  const { code } = await runShell(script, dir);
  if (code !== 0) {
    const d = diagnose(`exit ${code}`);
    if (d) console.error(`\n💡 ${d.hint}`);
  }
  process.exit(code);
}

async function cmdAnalyze() {
  const bin = process.argv[3];
  const mode = process.argv[4] || 'info';
  if (!bin) return console.error('用法：spark analyze <二进制> [info|symbols|strings|imports|sections]');
  const tc = toolchain();
  const rabin2 = tc.reverseBin ? path.join(tc.reverseBin, 'rabin2') : 'rabin2';
  const map = { info: '-I', symbols: '-s', strings: '-zz', imports: '-i', sections: '-S', entry: '-e' };
  const args = map[mode] || '-I';
  await runShell(`"${rabin2}" ${args} "${bin}"`, process.cwd());
}

const cmd = process.argv[2];
const table = {
  doctor: cmdDoctor,
  projects: cmdProjects,
  script: cmdScript,
  build: cmdBuild,
  analyze: cmdAnalyze,
};

if (!table[cmd]) {
  console.log(`spark —— Workbench 的命令行伴生工具

  doctor                      体检工具链
  projects                    列出候选项目
  script <dir> [选项]          打印构建脚本
  build  <dir> [选项]          直接编译
  analyze <bin> [mode]        逆向分析

选项：--arch --format --release --clean --ollvm <级别> --passes a,b --jobs N --sdk <名>
`);
  process.exit(cmd ? 1 : 0);
}
table[cmd]();
