/**
 * trolltools.mjs —— 巨魔工具链发现（insert_dylib / install_name_tool / ldid / ct_bypass / chown）
 *
 * 思路：这些工具不一定都在 PATH 里。按优先级从这些地方找：
 *   1. 用户设置里指定的目录
 *   2. Rein 的 helpers（DSH.app/helpers 里有一套裁过的）
 *   3. Rein 的 theos-root/usr/bin（Darwin 版 binutils 全家桶）
 *   4. 系统 PATH
 *
 * 纯 JS、不依赖 fs 之外的东西，方便在真机 / CLI / CI 里复用。
 */
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';

/** 工具清单：name → 可能出现的文件名（按优先级） */
export const TOOL_ALIASES = {
  insert_dylib: ['insert_dylib'],
  install_name_tool: ['install_name_tool', 'llvm-install-name-tool'],
  optool: ['optool'],
  ldid: ['ldid', 'ldid2'],
  ct_bypass: ['ct_bypass'],
  chown: ['chown'],
  cp: ['cp', 'cp-15'],
  mv: ['mv', 'mv-15'],
  strip: ['strip'],
  codesign_patch: ['ct_bypass'],
};

/** 巨魔注入必需的三件套 */
export const REQUIRED_FOR_INJECT = ['insert_dylib', 'ldid', 'chown'];
/** 可选但强烈建议 */
export const RECOMMENDED = ['install_name_tool', 'ct_bypass'];

/**
 * Rein 把一套裁过的 Darwin 工具放在 DSH.app/helpers 里（insert_dylib、ldid 都在那儿）。
 * 这个函数顺着 REIN_ROOT 往上找 Bundle/Application/<UUID>/X.app/helpers，
 * 让 Workbench 不用用户手动指路径也能用上它们。
 */
function siblingHelperDirs() {
  const roots = [
    process.env.SPARK_APP_PATH,
    process.env.SPARK_BUNDLE_PATH,
    process.env.SPARK_REIN_ROOT || process.env.REIN_ROOT,
  ].filter(Boolean);

  const out = [];
  for (const start of roots) {
    if (!start) continue;
    // 同级 App 的 helpers：…/Bundle/Application/<UUID>/X.app/helpers
    const appDir = path.dirname(start);
    out.push(path.join(appDir, 'helpers'));
    // 自己所在 App 的 helpers
    out.push(path.join(start, 'helpers'));
  }
  // Bundle/Application 下逐个 App 找一遍（真机上通常只有一两个）
  const appRoot = '/private/var/containers/Bundle/Application';
  for (const start of roots) {
    if (!start.startsWith(appRoot)) continue;
    try {
      const rest = start.slice(appRoot.length + 1).split('/')[0];
      const uuidDir = path.join(appRoot, rest);
      for (const name of fs.readdirSync(uuidDir)) {
        if (name.endsWith('.app')) out.push(path.join(uuidDir, name, 'helpers'));
      }
    } catch {
      /* 没有权限就算了 */
    }
  }
  return [...new Set(out)];
}

function isExecutable(p) {
  try {
    fs.accessSync(p, fs.constants.X_OK);
    return fs.statSync(p).isFile();
  } catch {
    return false;
  }
}

/**
 * 给出候选搜索目录。
 * @param {object} opts
 * @param {string} [opts.reinRoot]   Rein 根目录
 * @param {string[]} [opts.extraDirs] 额外目录
 * @param {string} [opts.bundlePath] App 包路径（DSH.app/helpers 就在这里）
 */
export function searchDirectories(opts = {}) {
  const home = process.env.HOME || os.homedir();
  const reinRoot = opts.reinRoot || process.env.SPARK_REIN_ROOT || process.env.REIN_ROOT ||
    path.join(home, 'Documents/Rein');
  const dirs = [
    ...(opts.extraDirs || []),
    ...siblingHelperDirs(),
    path.join(reinRoot, 'tools/reverse/bin'),
    path.join(reinRoot, 'helpers'),
    path.join(reinRoot, 'tools/theos-root/usr/bin'),
    path.join(reinRoot, 'tools/bin'),
    '/var/jb/usr/bin',
    '/usr/bin',
    '/usr/local/bin',
    '/bin',
  ];
  if (opts.bundlePath) dirs.unshift(path.join(opts.bundlePath, 'helpers'));
  if (process.env.PATH) dirs.push(...process.env.PATH.split(':').filter(Boolean));
  return [...new Set(dirs)];
}

/**
 * 扫描工具链。
 * @returns {{found: Record<string,string|null>, required: string[], recommended: string[],
 *            missingRequired: string[], missingRecommended: string[], ready: boolean}}
 */
export function detectTools(opts = {}) {
  const dirs = searchDirectories(opts);
  const found = {};
  for (const [tool, aliases] of Object.entries(TOOL_ALIASES)) {
    found[tool] = null;
    for (const dir of dirs) {
      for (const alias of aliases) {
        const candidate = path.isAbsolute(alias) ? alias : path.join(dir, alias);
        if (isExecutable(candidate)) {
          found[tool] = candidate;
          break;
        }
      }
      if (found[tool]) break;
    }
  }
  const missingRequired = REQUIRED_FOR_INJECT.filter((t) => !found[t]);
  const missingRecommended = RECOMMENDED.filter((t) => !found[t]);
  return {
    found,
    required: REQUIRED_FOR_INJECT,
    recommended: RECOMMENDED,
    missingRequired,
    missingRecommended,
    ready: missingRequired.length === 0,
  };
}

/** 一句话状态，给 UI 用 */
export function summarizeTools(report) {
  const parts = [];
  for (const t of [...report.required, ...report.recommended]) {
    parts.push(`${report.found[t] ? '✓' : '✗'}${t}`);
  }
  return parts.join('  ');
}

/** 缺什么该怎么补 —— 给用户的具体建议 */
export function remediesFor(report) {
  const out = [];
  if (report.missingRequired.includes('insert_dylib')) {
    out.push('缺 insert_dylib：可从 Rein 的 helpers 目录复制，或从 github.com/tyilo/insert_dylib 自行编译。');
  }
  if (report.missingRequired.includes('ldid')) {
    out.push('缺 ldid：Rein 的 helpers/ldid 或 theos/usr/bin/ldid 里都有，拷到 /usr/bin 并 chmod +x。');
  }
  if (report.missingRequired.includes('chown')) {
    out.push('缺 chown：theos-root/usr/bin/chown 可以直接用。');
  }
  if (report.missingRecommended.includes('ct_bypass')) {
    out.push(
      '没有 ct_bypass：注入后的 App 只能在越狱环境下运行。' +
        '要像 TrollFools 那样「就地装进巨魔」，需要 CoreTrust 绕过工具（TrollFools 内置了这份二进制）。',
    );
  }
  if (report.missingRecommended.includes('install_name_tool')) {
    out.push('缺 install_name_tool：一般不影响主流程，只影响 dylib 安装路径的规范化。');
  }
  return out;
}
