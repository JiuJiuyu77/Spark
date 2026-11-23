#!/usr/bin/env node
/**
 * gen-build-script.mjs —— 把「项目 + 选项 + 工具链」翻译成一段可直接执行的构建脚本。
 *
 * 用途：
 *   · CLI 里想看一眼 Workbench 到底会执行什么
 *   · CI 里生成构建脚本给 sh 跑
 *   · 把脚本贴给别人复现问题
 *
 * 用法：
 *   node scripts/gen-build-script.mjs --path /var/mobile/MyTweak --ollvm strong
 *   node scripts/gen-build-script.mjs --demo            # 打印一个示例脚本
 *   node scripts/gen-build-script.mjs --json            # 同时输出解析出的选项
 */
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';

import { buildScript, defaultOptions, detectProject } from '../ShareKit/src/model.js';

function arg(name, fallback = null) {
  const i = process.argv.indexOf(`--${name}`);
  if (i < 0) return fallback;
  const v = process.argv[i + 1];
  return v && !v.startsWith('--') ? v : true;
}

const HOME = process.env.HOME || os.homedir();
const demo = arg('demo');

const projectPath = demo ? '/var/mobile/Documents/Workbench/projects/DemoTweak' : arg('path', process.cwd());
const options = {
  ...defaultOptions(),
  arch: arg('arch', 'arm64'),
  format: arg('format', 'rootless'),
  debug: arg('debug', '1') !== '0',
  clean: !!arg('clean', false),
  ollvm: !!arg('ollvm', false),
  obfuscation: arg('ollvm') || 'none',
  jobs: Number(arg('jobs', 4)),
};
if (arg('release')) {
  options.debug = false;
  options.strip = true;
}

// 探测工具链（只做「有没有」的判断，不执行任何东西）
const reinRoot = process.env.REIN_ROOT || path.join(HOME, 'Documents/Rein');
const theosCandidates = [
  path.join(reinRoot, 'tools/theos-full'),
  path.join(reinRoot, 'tools/theos-local'),
  path.join(reinRoot, 'theos-root/theos'),
];
const theos = theosCandidates.find((p) => fs.existsSync(p)) || '/opt/theos';
const sdkDir = path.join(theos, 'sdks');
let sdk = null;
if (fs.existsSync(sdkDir)) {
  const found = fs
    .readdirSync(sdkDir)
    .filter((n) => n.startsWith('iPhoneOS') && n.endsWith('.sdk'))
    .sort();
  if (found.length) sdk = path.join(sdkDir, found[found.length - 1]);
}
const ollvmRoot = [path.join(reinRoot, 'tools/ollvm'), path.join(reinRoot, 'ollvm')].find(
  (p) => fs.existsSync(path.join(p, 'bin/clang')),
);

const profile = { theos, sdk, ollvmRoot };

let projectInfo = null;
if (!demo && fs.existsSync(projectPath)) {
  const io = {
    hasFile: (rel) => fs.existsSync(path.join(projectPath, rel)),
    readFile: (rel) => {
      try {
        return fs.readFileSync(path.join(projectPath, rel), 'utf8');
      } catch {
        return null;
      }
    },
  };
  projectInfo = detectProject(io);
}

const script = buildScript({ path: projectPath }, options, profile);
process.stdout.write(script);

if (process.argv.includes('--json')) {
  process.stderr.write(
    JSON.stringify({ project: projectPath, projectInfo, options, profile }, null, 2) + '\n',
  );
}
