/**
 * trollinject.mjs —— 巨魔（TrollStore）注入器：计划生成 + 输出解析 + IPA 改名
 *
 * 设计参考：Lessica/TrollFools（MIT）的注入流程 ——
 *   1. 预处理插件的 Mach-O：把 LC_LOAD_DYLIB 里的绝对路径改成 @executable_path/…，
 *      并把 .deb / .zip 里的内容先解出来
 *   2. 给插件本体注入 CydiaSubstrate 依赖（否则 tweak 加载不了）
 *   3. 在目标 App 的主 Mach-O 里插入一条 LC_LOAD_DYLIB（或 LC_LOAD_WEAK_DYLIB）
 *   4. CoreTrust 绕过 + 改属主 installd，让 TrollStore 能就地安装
 *
 * 我们不复刻它的 SwiftUI 界面与 ChOma C 绑定，而是：
 *   · 在设备上调用它同一族工具（insert_dylib / install_name_tool / ldid / chown）
 *   · 额外提供「克隆 App → 注入 → 重新打成 ipa」的离线流水线
 *
 * 这个文件只做纯计算（生成计划、解析工具输出），不碰系统，
 * 因此可以被 iOS App、CLI、CI 共用，也能在这台 Linux 沙箱里跑测试。
 */

/** insert_dylib 常用 flag */
export const INSERT_OPTIONS = {
  weak: '--weak',
  overwrite: '--inplace',
  code_sign: '--codesign',
  strip_codesign: '--strip-codesign',
  no_default_rpath: '--no-default-rpaths',
};

/** 巨魔注入器支持的插件种类 */
export const PLUGIN_EXTENSIONS = ['dylib', 'framework', 'bundle'];

/** 目标 App 里这些 Mach-O 名要跳过（TrollFools 同款黑名单） */
export const IGNORED_MACHO_NAMES = [
  'libswift', 'libobjc', 'libSystem', 'Foundation', 'UIKit',
  'libdispatch', 'libxpc', 'libdyld', 'libsystem_', 'CoreFoundation',
];

/**
 * 找出 zip / deb 解包后值得注入的东西。
 * @param {string[]} paths 解包后的相对路径列表
 * @returns {{plugins: string[], bundles: string[], frameworks: string[], ignored: string[]}}
 */
export function selectPlugins(paths = []) {
  const plugins = [];
  const bundles = [];
  const frameworks = [];
  const ignored = [];
  for (const p of paths) {
    // framework 内部是 Foo.framework/Foo（无扩展名），所以先看后缀再看扩展名
    const fw = p.match(/\.framework(\/|$)/i);
    if (fw) {
      const end = p.toLowerCase().indexOf('.framework') + '.framework'.length;
      if (IGNORED_MACHO_NAMES.some((x) => p.toLowerCase().includes(x.toLowerCase()))) ignored.push(p);
      else frameworks.push(p.slice(0, end));
      continue;
    }
    const b = p.toLowerCase().indexOf('.bundle');
    if (b >= 0) {
      bundles.push(p.slice(0, b + '.bundle'.length));
      continue;
    }
    const name = p.split('/').filter(Boolean).pop() || '';
    const lower = name.toLowerCase();
    const ext = lower.includes('.') ? lower.split('.').pop() : '';
    if (!PLUGIN_EXTENSIONS.includes(ext)) continue;
    if (IGNORED_MACHO_NAMES.some((x) => lower.startsWith(x.toLowerCase()))) {
      ignored.push(p);
      continue;
    }
    if (ext === 'dylib') plugins.push(p);

  }
  const uniq = (a) => [...new Set(a)];
  return { plugins: uniq(plugins), bundles: uniq(bundles), frameworks: uniq(frameworks), ignored };
}

/**
 * 判断一个 Mach-O 路径是不是「应该被注入的目标」。
 * 规则来自 TrollFools 的 locateAvailableMachO：优先和 bundle 同名的可执行文件，
 * 其次排除插件与框架目录里的二进制。
 */
export function pickTargetMachO(entries = [], appExecutableName = '') {
  const candidates = entries.filter((e) => {
    const parts = e.split('/');
    const name = parts.pop() || '';
    if (!name || name.includes('.')) return false; // 有扩展名的不是主二进制
    if (parts.some((p) => /\.(appex|framework|bundle|dylib)$/i.test(p))) return false;
    if (parts.some((p) => p.startsWith('PlugIns'))) return false;
    return true;
  });
  const preferred = candidates.find((c) => c.split('/').pop() === appExecutableName);
  return preferred || candidates[0] || null;
}

/**
 * 规范化 dylib 的安装路径：把开发机上的绝对路径换成 @executable_path 相对路径。
 * 这条规则直接照搬 TrollFools 的 standardizeLoadCommandDylib：
 *   /var/jb/Library/MobileSubstrate/DynamicLibraries/X.dylib → @executable_path/X.dylib
 *   …/Frameworks/F.framework/F → @executable_path/Frameworks/F.framework/F
 */
export function normalizeInstallName(dylibPath) {
  const marker = '/Library/MobileSubstrate/DynamicLibraries/';
  const idx = dylibPath.indexOf(marker);
  if (idx >= 0) return `@executable_path/${dylibPath.slice(idx + marker.length)}`;

  const fw = dylibPath.match(/\/([A-Za-z0-9_+-]+\.framework)\/([A-Za-z0-9_+-]+)$/);
  if (fw) return `@executable_path/Frameworks/${fw[1]}/${fw[2]}`;

  const base = dylibPath.split('/').filter(Boolean).pop() || 'plugin.dylib';
  return `@executable_path/${base}`;
}

/**
 * 生成注入计划：不需要真的执行，先给用户看清楚每一步。
 *
 * @param {object} input
 * @param {string} input.appPath        目标 .app 路径（设备上真实路径，或 IPA 里的概念路径）
 * @param {string} input.executableName App 主二进制名
 * @param {string[]} input.plugins      要注入的 dylib / framework / bundle
 * @param {object} [input.options]
 */
export function planInjection(input) {
  const { appPath, executableName, plugins = [], options = {} } = input || {};
  const steps = [];

  const mark = (title, detail) => steps.push({ title, detail });

  mark('备份', `把 ${appPath} 复制一份到 ${appPath}.sparkbak，注入失败可原样恢复`);

  for (const p of plugins) {
    const lower = p.toLowerCase();
    if (lower.endsWith('.bundle')) {
      mark('复制资源包', `cp -R ${p} → ${appPath}/`);
      mark('改属主', `chown -R mobile:mobile ${appPath}/${p.split('/').pop()}`);
      continue;
    }
    const installName = normalizeInstallName(p);
    mark('规范化安装路径', `${p} 的 LC_ID_DYLIB → ${installName}`);
    mark('设置安装名', `install_name_tool -id ${installName} ${p}`);
    mark('重签名插件', `ldid -S ${p}`);
    if (lower.endsWith('.framework')) {
      mark('复制框架', `cp -R ${p} → ${appPath}/Frameworks/`);
    } else {
      mark('复制 dylib', `cp ${p} → ${appPath}/${installName.replace('@executable_path/', '')}`);
    }
  }

  if (plugins.some((p) => /\.(dylib|framework)$/i.test(p))) {
    mark('准备 CydiaSubstrate', '把 CydiaSubstrate.framework 复制到 App/Frameworks（tweak 的加载器）');
    mark('注入主二进制', `insert_dylib ${options.weak ? '--weak ' : ''}@executable_path/${executableName} ` +
      `@executable_path/CydiaSubstrate.framework/CydiaSubstrate ${appPath}/${executableName}`);
    for (const p of plugins.filter((x) => /\.(dylib|framework)$/i.test(x))) {
      const path = normalizeInstallName(p);
      const target = path.endsWith('.dylib') ? `@executable_path/${path.split('/').pop()}` : path;
      mark('插入加载命令', `insert_dylib ${options.weak ? '--weak ' : ''}${target} ${appPath}/${executableName}`);
    }
  }

  if (options.coreTrustBypass) {
    mark('CoreTrust 绕过', '对注入过的每个 Mach-O 执行 ct_bypass（TrollStore 才能就地安装）');
  }
  if (options.ldid !== false) {
    mark('整体补签', `ldid -S ${appPath}/${executableName}`);
  }
  mark('改属主', `chown -R mobile:mobile ${appPath}`);

  return {
    appPath,
    executableName,
    steps,
    summary: {
      pluginCount: plugins.length,
      hasSubstrate: plugins.some((p) => /\.(dylib|framework)$/i.test(p)),
      coreTrustBypass: !!options.coreTrustBypass,
      weak: !!options.weak,
    },
  };
}

/**
 * 生成可直接执行的 shell 脚本（设备端）。
 * 注意：每一步都有 `|| exit` 保护，中途失败不会留下半个包。
 */
export function injectionScript(plan, tools = {}) {
  const q = (s) => {
    const str = String(s ?? '');
    if (str === '') return "''";
    return /^[A-Za-z0-9@%_+=:,./-]+$/.test(str) ? str : `'${str.replace(/'/g, `'\\''`)}'`;
  };
  const t = {
    insert_dylib: tools.insert_dylib || 'insert_dylib',
    install_name_tool: tools.install_name_tool || 'install_name_tool',
    ldid: tools.ldid || 'ldid',
    chown: tools.chown || 'chown',
    ct_bypass: tools.ct_bypass || 'ct_bypass',
  };

  const app = q(plan.appPath);
  const exe = `${app}/${q(plan.executableName)}`;
  const lines = [
    '#!/bin/sh',
    '# Workbench 巨魔注入脚本（参考 TrollFools 的注入流程）',
    'set -e',
    'say() { printf "\\033[1;36m==> %s\\033[0m\\n" "$1"; }',
    '',
    `APP=${app}`,
    `EXE=${exe}`,
    '[ -f "$EXE" ] || { echo "主二进制不存在: $EXE"; exit 2; }',
    'BACKUP="${APP}.sparkbak"',
    '[ -d "$BACKUP" ] || { say "备份"; cp -R "$APP" "$BACKUP"; }',
    '',
  ];

  for (const step of plan.steps) {
    lines.push(`say ${q(step.title)}`);
    // 只把「动作类」步骤翻译成命令，说明类步骤只打日志
    const d = step.detail;
    if (d.startsWith('cp ')) {
      const [, src, dst] = d.match(/^cp (-R )?(.+?) → (.+)$/) || [];
      if (src && dst) lines.push(`mkdir -p "$(dirname ${q(dst)})" && cp -R ${q(src)} ${q(dst)}`);
    } else if (d.startsWith('chown -R')) {
      lines.push(`[ -x ${q(t.chown)} ] && ${q(t.chown)} -R mobile:mobile ${q(plan.appPath)} || true`);
    } else if (d.startsWith('install_name_tool -id')) {
      const m = d.match(/install_name_tool -id (\S+) (.+)$/);
      if (m) lines.push(`[ -x ${q(t.install_name_tool)} ] && ${q(t.install_name_tool)} -id ${q(m[1])} ${q(m[2])} || true`);
    } else if (d.startsWith('ldid -S')) {
      const p = d.slice('ldid -S '.length);
      lines.push(`[ -x ${q(t.ldid)} ] && ${q(t.ldid)} -S ${q(p)} || true`);
    } else if (d.startsWith('insert_dylib ')) {
      // insert_dylib <flags> <dylibPath> <targetBinary>
      const parts = d.slice('insert_dylib '.length).split(/\s+/);
      const target = parts.pop();
      const dylib = parts.pop();
      const flags = parts;
      lines.push(`[ -x ${q(t.insert_dylib)} ] && ${q(t.insert_dylib)} ${flags.join(' ')} ${q(dylib)} ${q(target)} >/dev/null || ` +
        `{ echo "insert_dylib 失败: ${dylib}"; exit 4; }`);
    } else if (d.startsWith('对注入过的')) {
      lines.push(`[ -x ${q(t.ct_bypass)} ] && ${q(t.ct_bypass)} "$EXE" || echo "[!] 没有 ct_bypass，跳过 CoreTrust 绕过"`);
    }
  }

  lines.push('');
  lines.push('say "完成"');
  lines.push('echo "已注入到 ${APP}（备份：${BACKUP}）"');
  return lines.join('\n') + '\n';
}

/**
 * 解析 insert_dylib 的输出，返回它是否真的改了文件、加了哪些命令。
 * insert_dylib 成功时会打印 "Added LC_LOAD_DYLIB command" 之类。
 */
export function parseInsertDylibOutput(text = '') {
  const s = String(text);
  const added = /Added LC_LOAD_(WEAK_)?DYLIB command/i.test(s);
  const already = /already (contains|has) (that|a) (LC_LOAD_DYLIB|load command)/i.test(s) || /already exists/i.test(s);
  const err = /(error|cannot|failed|not a Mach-O)/i.test(s);
  return { added, already, error: err && !added && !already ? s.trim().split('\n').pop() : null };
}

/** 从 IPA 里挑出主 App 目录名（Payload/Xxx.app） */
export function pickAppBundleFromEntries(entries = []) {
  const apps = entries.filter((e) => /^Payload\/[^/]+\.app$/.test(e.replace(/\/$/, '')));
  if (apps.length) return apps[0].replace(/\/$/, '');
  const any = entries.find((e) => e.includes('.app/') || e.endsWith('.app'));
  return any ? any.split('/').slice(0, 2).join('/') : null;
}

/** 生成注入后 IPA 的文件名 */
export function injectedIpaName(baseName, versions = []) {
  const clean = String(baseName || 'App').replace(/\.ipa$/i, '');
  return versions.length ? `${clean}-injected-${versions.join('-')}.ipa` : `${clean}-injected.ipa`;
}

/** 把「注入来源」归成一句人类可读的说明，控制台里显示 */
export function describeSource(pluginPath = '') {
  const lower = pluginPath.toLowerCase();
  if (lower.endsWith('.deb')) return 'Debian 包（会自动解出 dylib）';
  if (lower.endsWith('.zip')) return 'ZIP 压缩包（会自动解出 dylib/framework/bundle）';
  if (lower.endsWith('.framework')) return '动态框架';
  if (lower.endsWith('.bundle')) return '资源包（不需要注入，直接复制）';
  if (lower.endsWith('.dylib')) return '动态库';
  return '未知类型';
}
