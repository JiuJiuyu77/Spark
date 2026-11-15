/**
 * ReinBuild 共享模型 —— 这是 App / Worker / CI 三端唯一的一份「真相」。
 *
 * 为什么要单独一份 JS：iOS 原生 App 里跑的是 Node 环境的逻辑（判断项目类型、
 * 拼 make 参数、解析错误），GitHub Actions 和 Cloudflare Worker 也要用同一套
 * 判定，否则「本地能编、CI 编不过」这种锅会没完没了。
 *
 * 约定：全部纯函数，不碰文件系统（fs 由调用方注入），这样浏览器 / Worker 也能跑。
 */

/** 项目类型 */
export const ProjectKind = {
  TWEAK: 'tweak',
  APPLICATION: 'application',
  LIBRARY: 'library',
  TOOL: 'tool',
  BUNDLE: 'bundle',
  NODE: 'node',
  SCRIPT: 'script',
  UNKNOWN: 'unknown',
};

/** 包格式 */
export const PackageFormat = {
  DEB: 'deb',
  ROOTLESS: 'rootless',
  APP: 'app',
  TIPA: 'tipa',
};

/** 架构 */
export const Arch = {
  ARM64: 'arm64',
  ARM64E: 'arm64e',
  BOTH: 'both',
};

/** 混淆强度 */
export const Obfuscation = {
  NONE: 'none',
  LIGHT: 'light',
  BALANCED: 'balanced',
  STRONG: 'strong',
  CUSTOM: 'custom',
};

/** Rein 里 Arkari LLVM 提供的 5 个 pass，flags 与 manifest.json 完全一致 */
export const OLLVM_PASSES = {
  indbr: { title: 'Indirect Branch（间接跳转）', flags: ['-mllvm', '-irobf', '-mllvm', '--irobf-indbr'] },
  icall: { title: 'Indirect Call（间接调用）', flags: ['-mllvm', '-irobf', '-mllvm', '--irobf-icall'] },
  indgv: { title: 'Indirect Globals（间接全局）', flags: ['-mllvm', '-irobf', '-mllvm', '--irobf-indgv'] },
  cse: { title: 'C String Encryption（字符串加密）', flags: ['-mllvm', '-irobf', '-mllvm', '--irobf-cse'] },
  cff: { title: 'Control Flow Flattening（控制流平坦化）', flags: ['-mllvm', '-irobf', '-mllvm', '--irobf-cff'] },
};

/** 混淆强度的预设组合（与 Rein 的 recommended_presets 对齐，并给出更保守/更强的档位） */
export const OBFUSCATION_PRESETS = {
  none: [],
  light: ['indbr', 'cse'],
  balanced: ['indbr', 'icall', 'cse'],
  strong: ['indbr', 'icall', 'indgv', 'cse', 'cff'],
};

/** 默认选项 */
export function defaultOptions() {
  return {
    arch: Arch.ARM64,
    format: PackageFormat.ROOTLESS,
    debug: true,
    clean: false,
    finalize: true,
    ldid: true,
    strip: false,
    ollvm: false,
    obfuscation: Obfuscation.NONE,
    passes: [],
    parallel: true,
    jobs: 4,
    extraArgs: '',
    extraEnv: '',
    version: '',
  };
}

/** 把混淆强度展开成 pass 列表 */
export function passesForObfuscation(level, custom = []) {
  if (level === Obfuscation.CUSTOM) return [...custom];
  const preset = OBFUSCATION_PRESETS[level] || [];
  return [...preset];
}

/** 把 pass 列表展开成 clang flags */
export function flagsForPasses(passes = []) {
  const out = [];
  for (const p of passes) {
    const def = OLLVM_PASSES[p];
    if (def) out.push(...def.flags);
  }
  return out;
}

/**
 * 解析 Makefile 里的 NAME 变量
 * 只认行首定义、跳过注释，避免把 $(TWEAK_NAME) 之类的引用也当成名字
 */
export function parseMakefileNames(makefileText = '') {
  const result = {};
  const vars = [
    ['TWEAK_NAME', ProjectKind.TWEAK],
    ['APPLICATION_NAME', ProjectKind.APPLICATION],
    ['LIBRARY_NAME', ProjectKind.LIBRARY],
    ['TOOL_NAME', ProjectKind.TOOL],
    ['BUNDLE_NAME', ProjectKind.BUNDLE],
    ['BUNDLE_ID', null],
    ['ARCHS', null],
    ['TARGET', null],
  ];
  const lines = makefileText.split(/\r?\n/);
  for (const raw of lines) {
    const line = raw.trim();
    if (!line || line.startsWith('#')) continue;
    for (const [name, kind] of vars) {
      const re = new RegExp(`^${name}\\s*[:+?]?=\\s*(.+)$`);
      const m = line.match(re);
      if (!m) continue;
      const value = m[1].trim().replace(/^["']|["']$/g, '');
      if (value.startsWith('$')) continue; // 引用不算
      result[name] = value;
      if (kind && !result.kind) {
        result.kind = kind;
        result.executable = value;
      }
    }
  }
  return result;
}

/** 解析 debian control */
export function parseControl(controlText = '') {
  const out = {};
  for (const raw of controlText.split(/\r?\n/)) {
    const line = raw.trim();
    if (!line || line.startsWith('#')) continue;
    const idx = line.indexOf(':');
    if (idx < 0) continue;
    const key = line.slice(0, idx).trim().toLowerCase();
    const value = line.slice(idx + 1).trim();
    if (!out[key]) out[key] = value;
  }
  return out;
}

/**
 * 判断一个目录是不是 Theos 项目、什么类型。
 * @param {{ hasFile: (rel: string) => boolean, readFile: (rel: string) => string|null }} io
 */
export function detectProject(io) {
  const hasMakefile = io.hasFile('Makefile');
  const hasPackageJson = io.hasFile('package.json');
  const hasBuildSh = io.hasFile('build.sh');
  const info = {
    isTheos: hasMakefile,
    kind: ProjectKind.UNKNOWN,
    executable: null,
    packageId: null,
    version: null,
    archs: null,
    target: null,
  };

  if (hasMakefile) {
    const mk = parseMakefileNames(io.readFile('Makefile') || '');
    Object.assign(info, {
      kind: mk.kind || ProjectKind.UNKNOWN,
      executable: mk.executable || null,
      archs: mk.ARCHS || null,
      target: mk.TARGET || null,
    });
  }

  if (io.hasFile('control')) {
    const c = parseControl(io.readFile('control') || '');
    info.packageId = c.package || null;
    info.version = c.version || null;
  }

  if (hasPackageJson) {
    try {
      const pj = JSON.parse(io.readFile('package.json') || '{}');
      info.name = pj.name;
      info.version = info.version || pj.version;
      if (!hasMakefile) info.kind = ProjectKind.NODE;
    } catch {
      /* 忽略坏 JSON */
    }
  }

  if (!hasMakefile && !hasPackageJson && hasBuildSh) info.kind = ProjectKind.SCRIPT;
  return info;
}

/** 把选项翻译成 make 环境变量（与 Native/ObjC/RBModels.m 一一对应） */
export function makeEnvironment(options = {}) {
  const o = { ...defaultOptions(), ...options };
  const env = {};

  const archMap = {
    [Arch.ARM64]: 'arm64',
    [Arch.ARM64E]: 'arm64e',
    [Arch.BOTH]: 'arm64 arm64e',
  };
  env.ARCHS = archMap[o.arch] || 'arm64';
  env.TARGET = 'iphone:clang:latest:15.0';

  if (o.format === PackageFormat.ROOTLESS) env.THEOS_PACKAGE_SCHEME = 'rootless';
  else if (o.format === PackageFormat.DEB) env.THEOS_PACKAGE_SCHEME = '';

  if (o.debug) {
    env.DEBUG = '1';
    env.THEOS_DEBUG = '1';
    env.OPTFLAG = '-O0 -g';
  } else {
    env.DEBUG = '0';
    env.OPTFLAG = o.strip ? '-O2' : '-O2 -g';
  }
  if (o.strip) env.STRIP = '1';

  const passes = o.ollvm ? passesForObfuscation(o.obfuscation, o.passes) : [];
  if (passes.length) {
    const flags = flagsForPasses(passes).join(' ');
    // 新版 Theos 认 ADDITIONAL_CCFLAGS；老的 ADDITIONAL_CFLAGS/CPPFLAGS 会报 deprecate
    env.ADDITIONAL_CCFLAGS = flags;
    env.ADDITIONAL_OBJCFLAGS = flags;
    env.RB_OLLVM_PASSES = passes.join(',');
  }

  if (o.version) env.PACKAGE_VERSION = o.version;

  if (o.extraEnv) {
    for (const line of String(o.extraEnv).split(/\r?\n/)) {
      const i = line.indexOf('=');
      if (i <= 0) continue;
      env[line.slice(0, i).trim()] = line.slice(i + 1);
    }
  }
  return env;
}

/** 把选项翻译成 make 参数 */
export function makeArguments(options = {}) {
  const o = { ...defaultOptions(), ...options };
  const args = [];
  if (o.clean) args.push('clean');
  if (o.finalize && o.format !== PackageFormat.APP) args.push('package');
  else args.push('all');
  if (o.parallel) args.push(`-j${Math.max(1, o.jobs || 4)}`);
  // .app 产物不需要 deb 打包流程，也就没有 FINALPACKAGE
  if (o.finalize && o.format !== PackageFormat.APP) args.push('FINALPACKAGE=1');
  if (o.extraArgs) args.push(...String(o.extraArgs).trim().split(/\s+/).filter(Boolean));
  return args;
}

/** 生成完整的构建脚本（Linux/macOS/越狱设备通用） */
export function buildScript(project, options = {}, profile = {}) {
  const env = { ...makeEnvironment(options), ...(profile.env || {}) };
  const args = makeArguments(options);
  const cwd = project.path || '.';

  const q = shellQuote;
  const lines = [
    '#!/bin/sh',
    '# ReinBuild 生成的构建脚本',
    'set -o pipefail 2>/dev/null || true',
    'export LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8',
    'say() { printf "\\033[1;36m==> %s\\033[0m\\n" "$1"; }',
    'ok()  { printf "\\033[1;32m[ok] %s\\033[0m\\n" "$1"; }',
    'warn(){ printf "\\033[1;33m[!] %s\\033[0m\\n" "$1"; }',
    'begin=$(date +%s)',
    '',
    "say '准备环境'",
  ];

  if (profile.pathPrefix) lines.push(`export PATH=${q(profile.pathPrefix)}:"$PATH"`);
  if (profile.theos) lines.push(`export THEOS=${q(profile.theos)}`);
  if (profile.sdk) lines.push(`export THEOS_SDK=${q(profile.sdk)}`, `export SYSROOT=${q(profile.sdk)}`);
  if (profile.ollvmRoot) {
    lines.push(`export CA_TOOL_OLLVM_ROOT=${q(profile.ollvmRoot)}`);
    lines.push(`export CA_TOOL_OLLVM_CLANG=${q(profile.ollvmRoot + '/bin/clang')}`);
    lines.push(`export CA_TOOL_OLLVM_RESOURCE_DIR=${q(profile.ollvmRoot + '/lib/clang/16')}`);
    lines.push(`export CC=${q(profile.ollvmRoot + '/bin/clang')}`);
  }
  for (const [k, v] of Object.entries(env)) lines.push(`export ${k}=${q(v)}`);

  lines.push('', "say '工具链自检'");
  lines.push('command -v make >/dev/null 2>&1 && ok "make $(command -v make)" || { warn "缺少 make"; exit 3; }');
  // 编译器自检：有 OLLVM 就认真检查它，没有就只看 Theos 侧的 clang
  if (profile.ollvmRoot) {
    lines.push('CCBIN="$CA_TOOL_OLLVM_CLANG"; "$CCBIN" --version >/dev/null 2>&1 && ok "OLLVM 编译器 $("$CCBIN" --version | head -1)" || { warn "OLLVM clang 不可用（$CCBIN），可先关掉混淆重试"; exit 4; }');
  } else {
    lines.push('CCBIN="${THEOS_TOOLCHAIN:-}/clang-16"; [ -x "$CCBIN" ] && ok "Darwin clang $("$CCBIN" --version 2>/dev/null | head -1)" || warn "未找到 Darwin clang，若 Theos 报 toolchain 缺失请检查 theos-root/usr/bin"');
  }
  lines.push('command -v ldid >/dev/null 2>&1 && ok "ldid $(command -v ldid)" || warn "没有 ldid，打包后不会补签"');
  lines.push('[ -d "$THEOS" ] && ok "THEOS=$THEOS" || warn "THEOS 不存在"');
  lines.push('[ -z "$THEOS_SDK" ] || { [ -d "$THEOS_SDK" ] && ok "SDK=$THEOS_SDK" || warn "SDK 不存在: $THEOS_SDK"; }');

  lines.push('', `cd ${q(cwd)} || { echo "项目目录不存在: ${cwd}"; exit 2; }`);
  lines.push('say "工作目录 $(pwd)"');

  if (options.clean) {
    lines.push("say '清理旧产物'", 'rm -rf .theos/_ .theos/obj packages 2>/dev/null || true');
  }

  lines.push('', "say '开始编译'", `echo "+ make ${args.join(' ')}"`, 'make ' + args.map(q).join(' '), 'rc=$?');
  lines.push('end=$(date +%s)');
  lines.push('if [ $rc -ne 0 ]; then echo "[!] 编译失败，退出码 $rc"; exit $rc; fi');
  lines.push('ok "用时 $((end - begin)) 秒"');
  lines.push('', "say '产物'", 'ls -lh packages/*.deb .theos/_/ 2>/dev/null | sed "s/^/    /" || true');
  return lines.join('\n') + '\n';
}

/** 单引号包裹一个 shell 参数 */
export function shellQuote(s) {
  const str = String(s ?? '');
  if (str === '') return "''";
  if (/^[A-Za-z0-9@%_+=:,./-]+$/.test(str)) return str;
  return `'${str.replace(/'/g, `'\\''`)}'`;
}

/** 从一段 make/clang 输出里找出最可能的失败原因 */
export function diagnose(logText = '') {
  const s = String(logText).toLowerCase();
  const rules = [
    ['no such file or directory: \'make\'', '找不到 make：Theos 没装好，或 PATH 里没有 theos/bin。', 'toolchain'],
    ['theos/makefiles', 'THEOS 路径不对：找不到 Theos 的 makefiles 目录。', 'config'],
    ['cannot find sdk', '找不到 SDK：检查 SDK 名称与 theos/sdks 下的目录是否一致。', 'config'],
    ['logos', 'Logos 预处理失败：检查 .x 文件里的 %hook / %orig 语法。', 'source'],
    ['error: expected', 'C/ObjC 语法错误：看第一个 error 行指的位置。', 'source'],
    ['fatal error:', '头文件缺失：确认 SDK 或 vendor/include 里有对应头文件。', 'source'],
    ['ld: library not found', '链接不到库：检查 xxx_LIBRARIES 或 .tbd 是否在 SDK/vendor 内。', 'link'],
    ['undefined symbols', '缺实现或库：按 undefined symbol 名字补框架/源文件。', 'link'],
    ['code signature', '签名失败：确认 ldid 可执行。', 'sign'],
    ['permission denied', '权限不足：项目目录要在 /var/mobile 下且可写。', 'permission'],
    ['killed', '进程被杀，多半内存不足：关掉 -j 并行，或改用远程/CI 构建。', 'resource'],
    ['segmentation fault', '编译器自身崩溃：通常是 OLLVM 与某个源码不兼容，先关混淆试一次。', 'ollvm'],
  ];
  for (const [needle, hint, category] of rules) {
    if (s.includes(needle)) return { hint, category, needle };
  }
  return null;
}

/** 版本号比较：返回 -1 / 0 / 1，支持 16.5 vs 17.0 这种 */
export function compareVersions(a, b) {
  const pa = String(a).replace(/[^0-9.]/g, '').split('.').map(Number);
  const pb = String(b).replace(/[^0-9.]/g, '').split('.').map(Number);
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
    const x = pa[i] || 0;
    const y = pb[i] || 0;
    if (x !== y) return x < y ? -1 : 1;
  }
  return 0;
}

/** 在若干候选 SDK 里挑最合适的：优先 <= 目标版本的最新一个 */
export function pickSDK(sdkNames = [], prefer = '17.0') {
  if (!sdkNames.length) return null;
  const parsed = sdkNames
    .map((name) => ({ name, ver: (name.match(/iPhoneOS([\d.]+)\.sdk/) || [])[1] || '0' }))
    .sort((x, y) => compareVersions(x.ver, y.ver));
  const under = parsed.filter((p) => compareVersions(p.ver, prefer) <= 0);
  return (under.length ? under[under.length - 1] : parsed[0]).name;
}
