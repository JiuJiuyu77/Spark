/**
 * 运行时包清单 —— **唯一真相是 Native/Resources/runtime-manifest.json**。
 *
 * 本文件不再自己维护数据，只负责把那份 JSON 读出来并做轻量派生
 * （按 id 取、安装顺序、代理 URL）。
 *
 * 为什么改成这样：
 *   以前这里和 Native/ObjC/SPToolchainDownloader.m 各写一份，
 *   两边长期不一致 —— 体积（theos 标 114MB 实际 259MB、
 *   coretools 标 40MB 实际 9.9MB）、探测命令（coretools 写 usr/bin/sh
 *   但包里只有 bin/git）、解包路径（python 的 python3 在包顶层不在 bin/）
 *   全对不上。现在数据只有一份，改 JSON 即可，两端自动同步。
 *
 * 字段说明见 JSON 里的 note；ObjC 侧由 scripts/gen-runtime-manifest.py
 * 从同一份 JSON 生成编译期兜底，二者不会分叉。
 */

import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const MANIFEST_PATH = join(HERE, '..', '..', 'Native', 'Resources', 'runtime-manifest.json');

let _manifest = null;

/** 读清单（带缓存）。读不到直接抛 —— 静默降级会重新制造分叉。 */
export function manifest() {
  if (!_manifest) {
    const raw = readFileSync(MANIFEST_PATH, 'utf8');
    _manifest = JSON.parse(raw);
  }
  return _manifest;
}

/** 全部组件（顺序与 JSON 一致，索引与 ObjC 的 SPComponent 枚举对齐） */
export const RUNTIMES = manifest().components;

/** 镜像前缀 */
export const RUNTIME_PROXY_PREFIXES = manifest().proxyPrefixes || [];

/** 按 id 取 */
export function runtimeById(id) {
  return RUNTIMES.find((r) => r.id === id) || null;
}

/** 安装顺序：order 小的先，依赖在前 */
export function installOrder(list = RUNTIMES) {
  return [...list].sort((a, b) => a.order - b.order);
}

/** 把 GitHub 原始地址换成可用代理（直连失败时用） */
export function proxiedURLs(url) {
  return [url, ...RUNTIME_PROXY_PREFIXES.map((p) => p + url)];
}

/** 安装子目录名（与 Workbench-Runtime 的包 id 一致） */
export function sdkSubdirFor(runtimeId) {
  return runtimeId;
}

/** 体积（字节） */
export function sizeOf(runtime) {
  return Number(runtime?.bytes || 0);
}
