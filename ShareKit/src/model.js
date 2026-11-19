/**
 * Spark 共享模型 —— 这是 App / Worker / CI 三端唯一的一份「真相」。
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
  DEB: 'deb',           // 有根 rootful
  ROOTLESS: 'rootless', // 无根
  ROOTHIDE: 'roothide', // 隐根（roothide 越狱）
  APP: 'app',
  TIPA: 'tipa',
};

/** 包布局 → THEOS_PACKAGE_SCHEME 的映射（空串表示 rootful） */
export const PACKAGE_SCHEMES = {
  deb: '',
  rootless: 'rootless',
  roothide: 'roothide',
  app: '',
  tipa: '',
};

/** 架构 */
export const Arch = {
  ARM64: 'arm64',
  ARM64E: 'arm64e',
  BOTH: 'both',
};

/** 编译优化等级（对应 clang -O 档位，并附带 Theos 相关开关） */
export const Optimization = {
  O0: 'O0',      // 调试用，不优化，编译最快
  OG: 'Og',      // 调试友好优化（GCC 风格，clang 也支持）
  O1: 'O1',      // 轻度优化
  O2: 'O2',      // 默认发布档（推荐）
  O3: 'O3',      // 激进优化，体积/速度换编译时间
  OS: 'Os',      // 优化体积（插件常用，deb 更小）
  OZ: 'Oz',      // 极限压体积
  OFAST: 'Ofast',// O3 + 数学优化（谨慎：会改变浮点行为）
};

/** 各优化档位的实际 flag（含 Theos 会读的 OPTFLAG） */
// 调试符号（-g）会让编译和链接明显变慢，而 tweak 发布时几乎用不到。
// 之前每个档位都硬带 -g，实测是构建慢的主要原因之一。
// 现在只在「调试模式」下加，其余情况用 -gline-tables-only
// （只保留行号，崩溃栈还能定位，体积和耗时小很多）。
export const OPTIMIZATION_FLAGS = {
  O0: { opt: '-O0', extra: '-g' },
  Og: { opt: '-Og', extra: '-gline-tables-only' },
  O1: { opt: '-O1', extra: '-gline-tables-only' },
  O2: { opt: '-O2', extra: '-gline-tables-only' },
  O3: { opt: '-O3', extra: '-gline-tables-only' },
  Os: { opt: '-Os', extra: '-gline-tables-only' },
  Oz: { opt: '-Oz', extra: '' },
  Ofast: { opt: '-Ofast', extra: '-gline-tables-only' },
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
  // Arkari 23.x 起改名：cff → fla，并新增 cie / cfe
  fla: { title: 'Control Flow Flattening（控制流平坦化）', flags: ['-mllvm', '-irobf', '-mllvm', '--irobf-fla'] },
  cie: { title: 'Indirect Call Enhance（间接调用增强）', flags: ['-mllvm', '-irobf', '-mllvm', '--irobf-cie'] },
  cfe: { title: 'Control Flow Enhance（控制流增强）', flags: ['-mllvm', '-irobf', '-mllvm', '--irobf-cfe'] },
  // 兼容旧版 Arkari 16（Rein 自带的那一版）
  cff: { title: 'Control Flow Flattening（旧版 cff）', flags: ['-mllvm', '-irobf', '-mllvm', '--irobf-cff'] },
};

/** 混淆强度的预设组合（与 Rein 的 recommended_presets 对齐，并给出更保守/更强的档位） */
export const OBFUSCATION_PRESETS = {
  none: [],
  // 轻度：只加间接跳转与字符串加密，体积影响最小
  light: ['indbr', 'cse'],
  // 均衡：再加间接调用
  balanced: ['indbr', 'icall', 'cse'],
  // 强力：全部 7 个（LLVM 23 的 fla/cie/cfe 也在内）
  strong: ['indbr', 'icall', 'indgv', 'cse', 'fla', 'cie', 'cfe'],
  // 兼容旧版编译器（Rein 自带的 16.0.6）
  legacy: ['indbr', 'icall', 'indgv', 'cse', 'cff'],
};

/** 默认选项 */
export function defaultOptions() {
  return {
    arch: Arch.ARM64,
    format: PackageFormat.ROOTLESS,
    // 默认走「发布」配置：调试模式会强制 -O0 + THEOS_DEBUG=1，
    // 实测编译速度慢一倍以上，而 tweak 日常也不需要调试符号。
    debug: false,
    clean: false,
    finalize: true,
    ldid: true,
    strip: false,   // 需要排查符号时再开；开着会让链接多一步
    ollvm: false,
    obfuscation: Obfuscation.NONE,
    optimization: Optimization.O2,
    passes: [],
    parallel: true,
    jobs: 0,   // 0 = 自动按 CPU 核数（见 makeArguments）
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

/** 把选项翻译成 make 环境变量（与 Native/ObjC/SPModels.m 一一对应） */
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

  // 三种包布局：rootful（空）/ rootless / roothide
  env.THEOS_PACKAGE_SCHEME = PACKAGE_SCHEMES[o.format] ?? '';

  // 优化等级：debug 时强制 O0（否则断点乱跳），其余按用户选择
  const opt = o.debug && !o.optimization ? Optimization.O0
            : (OPTIMIZATION_FLAGS[o.optimization] ? o.optimization : Optimization.O2);
  const flags = OPTIMIZATION_FLAGS[opt] || OPTIMIZATION_FLAGS.O2;

  if (o.debug) {
    env.DEBUG = '1';
    env.THEOS_DEBUG = '1';
  } else {
    env.DEBUG = '0';
  }
  env.OPTFLAG = o.strip ? flags.opt : `${flags.opt} ${flags.extra}`.trim();
  // Theos 会把这些变量拼进编译命令，显式给一遍更保险
  env.RB_OPT_LEVEL = opt;
  if (o.strip) env.STRIP = '1';

  const passes = o.ollvm ? passesForObfuscation(o.obfuscation, o.passes) : [];
  if (passes.length) {
    const flags = flagsForPasses(passes).join(' ');
    // 新版 Theos 认 ADDITIONAL_CCFLAGS；老的 ADDITIONAL_CFLAGS/CPPFLAGS 会报 deprecate
    env.ADDITIONAL_CCFLAGS = flags;
    env.ADDITIONAL_OBJCFLAGS = flags;
    env.SP_OLLVM_PASSES = passes.join(',');
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
  if (o.parallel) {
    // 并行数：用户指定优先，否则按 CPU 核数。
    // 手机通常是 6 核（2 大 + 4 小），固定 -j4 用不满。
    let jobs = o.jobs || 0;
    if (!jobs) {
      const n = (typeof navigator !== 'undefined' && navigator.hardwareConcurrency) || 0;
      jobs = n > 0 ? Math.min(n, 8) : 4;
    }
    args.push(`-j${Math.max(1, jobs)}`);
  }
  // .app 产物不需要 deb 打包流程，也就没有 FINALPACKAGE
  if (o.finalize && o.format !== PackageFormat.APP) args.push('FINALPACKAGE=1');
  if (o.extraArgs) args.push(...String(o.extraArgs).trim().split(/\s+/).filter(Boolean));
  return args;
}

/** 生成完整的构建脚本（Linux/macOS/越狱设备通用） */
export function buildScript(project, options = {}, profile = {}) {
  const o = { ...defaultOptions(), ...options };
  const env = { ...makeEnvironment(o), ...(profile.env || {}) };
  const args = makeArguments(o);
  const cwd = project.path || '.';

  const q = shellQuote;
  const lines = [
    '#!/bin/sh',
    '# Spark 生成的构建脚本',
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
  // 内存遥测：编译大工程时能提前看到内存压力（Rein 的 boot.js 也这么干）
  // A6：内存遥测 —— 编译期间后台每 15 秒采样一次（借鉴 Rein 的 boot.js）
  // 一次性采样看不出趋势，长编译内存爬升才是真问题
  // 注意：模板字符串里 ${...} 会被 JS 吞掉，shell 变量要写成 \${...}
  lines.push(`mem() { if [ -r /proc/meminfo ]; then awk '/MemAvailable/{printf "    内存可用 %d MB\\n", $2/1024}' /proc/meminfo; else free=$(vm_stat 2>/dev/null | awk '/Pages free/{gsub("\\.","",$3);print int($3*16384/1048576)}'); [ -n "$free" ] && echo "    内存可用 \${free}MB"; fi; }`);
  lines.push(`( while :; do sleep 15; mem; done ) & MEMWATCH=$!`);
  lines.push(`trap 'kill $MEMWATCH 2>/dev/null' EXIT`);
  lines.push('mem');
  lines.push('command -v make >/dev/null 2>&1 && ok "make $(command -v make)" || { warn "缺少 make"; exit 3; }');
  // 编译器自检：有 OLLVM 就认真检查它，没有就只看 Theos 侧的 clang
  if (profile.ollvmRoot) {
    lines.push('CCBIN="$CA_TOOL_OLLVM_CLANG"; "$CCBIN" --version >/dev/null 2>&1 && ok "OLLVM 编译器 $("$CCBIN" --version | head -1)" || { warn "OLLVM clang 不可用（$CCBIN），可先关掉混淆重试"; exit 4; }');
  } else {
    // 从 PATH 里实际找，而不是依赖一个外部变量：
    // 之前用 ${THEOS_TOOLCHAIN:-}/clang-16，该变量从未被设置，
    // 结果每次都打印「未找到 Darwin clang」，误导排查方向。
    lines.push('CCBIN=$(command -v clang-16 2>/dev/null || command -v clang 2>/dev/null || true); ' +
               '[ -n "$CCBIN" ] && ok "编译器 $CCBIN $("$CCBIN" --version 2>/dev/null | head -1)" || ' +
               '{ warn "PATH 里没有 clang-16/clang"; exit 5; }');
    lines.push('command -v ld64 >/dev/null 2>&1 && ok "链接器 $(command -v ld64)" || ' +
               '{ warn "PATH 里没有 ld64，链接会失败"; exit 6; }');
  }
  lines.push('command -v ldid >/dev/null 2>&1 && ok "ldid $(command -v ldid)" || warn "没有 ldid，打包后不会补签"');
  // 身份检查：子进程必须是 root。
  //
  // TrollStore 装的 App 本身以 root 运行，子进程会继承；但如果 App
  // 被以 mobile 身份启动（或提权失败），make 会在写 .theos/、
  // 改 layout 权限时被拒，报一堆 Permission denied —— 很难看出是身份问题。
  // 这里直接判定，并把「为什么」写清楚。
  lines.push('U=$(id -u)');
  lines.push('if [ "$U" != "0" ]; then ' +
             '{ warn "子进程没有 root 权限（当前 uid=$U）"; ' +
             'warn "原因：Spark 以 mobile 身份启动，或提权失败"; ' +
             'warn "处理：用 TrollStore 重新安装 Spark（需要 platform-application 权限）"; ' +
             'warn "自查：设置 → 运行环境自检，看「子进程身份」一项"; ' +
             'exit 9; }; fi');
  lines.push('ok "子进程以 root 运行"');

  // THEOS 是编译前提：没有它 make 连 makefiles 都找不到。
  // 之前只是 warn，会一路跑到 make 才报一堆看不懂的错。
  lines.push('[ -n "${THEOS:-}" ] && [ -d "$THEOS" ] && ok "THEOS=$THEOS" || ' +
             '{ warn "THEOS 未设置或不存在（$THEOS）—— 请先在「设置 → 工具链」展开内置工具链"; exit 7; }');
  lines.push('[ -f "$THEOS/makefiles/common.mk" ] || { warn "THEOS 里没有 makefiles/common.mk，工具链不完整"; exit 8; }');
  lines.push('[ -z "$THEOS_SDK" ] || { [ -d "$THEOS_SDK" ] && ok "SDK=$THEOS_SDK" || warn "SDK 不存在: $THEOS_SDK"; }');

  lines.push('', `cd ${q(cwd)} || { echo "项目目录不存在: ${cwd}"; exit 2; }`);
  lines.push('say "工作目录 $(pwd)"');

  if (o.clean) {
    lines.push("say '清理旧产物'", 'rm -rf .theos/_ .theos/obj packages 2>/dev/null || true');
  }

  // Rein 的经验：真 root 环境下 Theos 的 fakeroot 是空壳，可以直接用 dpkg-deb 打包
  // 这里显式告诉 Theos：不要尝试 fauxsu / fakeroot-ng
  lines.push('');
  lines.push(`if [ "$(id -u)" = "0" ]; then ok '当前是 root，跳过 fakeroot 包装'; export THEOS_USE_FAKEROOT=0; fi`);
  lines.push('export COPYFILE_DISABLE=1');   // 避免 macOS/Linux 资源分叉文件进 deb
  // deb 压缩：xz -1 是速度/体积平衡点（默认 xz -6 在手机上慢得多）
  lines.push('export THEOS_PLATFORM_DEB_COMPRESSION_LEVEL=1');

  // 收尾用 trap 保证执行：
  // 之前「编译失败 → exit」跳过了后面的 report.json 生成，
  // 失败构建没有任何留档，事后无法查。
  lines.push('');
  lines.push(`write_report() {
  rc_final=\${1:-0}
  END=$(date +%s)
  {
    printf '{\\n'
    printf '  "project": "%s",\\n' ${JSON.stringify(project.path || '')}
    printf '  "options": { "arch": "%s", "format": "%s", "debug": %s },\\n' ${JSON.stringify(o.arch)} ${JSON.stringify(o.format)} '${o.debug ? 'true' : 'false'}'
    printf '  "artifacts": ['
    first=1
    for a in packages/*.deb; do
      [ -f "$a" ] || continue
      [ $first = 1 ] || printf ','
      first=0
      printf '\\n    "%s"' "$a"
    done
    printf '\\n  ],\\n'
    printf '  "durationSec": %s,\\n' "$((END - begin))"
    printf '  "exitCode": %s\\n' "$rc_final"
    printf '}\\n'
  } > report.json 2>/dev/null || true
}`);
  lines.push(`trap 'write_report $?' EXIT`);
  lines.push('');
  // .x 预展开：设备上的 perl 缺 libperl.dylib 跑不起来，
  // 所以在 make 之前用 Spark 自带预处理器把 .x 展开成 .m。
  // perl 可用时不干预（保持原生 Logos 行为）。
  lines.push('', "say 'Logos 预处理'");
  lines.push(`LOGOS_TOOL="${'$'}SPARK_TC/tools/spark-logos.py"`);
  lines.push('[ -f "$LOGOS_TOOL" ] || LOGOS_TOOL="/usr/share/spark/spark-logos.py"');
  lines.push('XLIST=$(ls *.x 2>/dev/null || true)');
  lines.push('if [ -n "$XLIST" ]; then');
  lines.push('  if perl -e "use Digest::MD5" 2>/dev/null; then');
  lines.push('    ok "perl 可用，使用原生 logos.pl"');
  lines.push('  elif command -v spark-logos >/dev/null 2>&1; then');
  lines.push('    for x in $XLIST; do');
  lines.push('      m="${x%.x}.m"');
  lines.push('      if spark-logos "$x" "$m"; then');
  lines.push('        ok "展开 $x → $m（内置预处理器）"');
  lines.push('        mv "$x" "$x.sparkbak" 2>/dev/null || true');
  lines.push('      else');
  lines.push('        warn "展开失败：$x"; exit 12');
  lines.push('      fi');
  lines.push('    done');
  lines.push('  elif [ -f "$LOGOS_TOOL" ] && command -v python3 >/dev/null 2>&1; then');
  lines.push('    for x in $XLIST; do');
  lines.push('      m="${x%.x}.m"');
  lines.push('      if python3 "$LOGOS_TOOL" "$x" "$m"; then');
  lines.push('        ok "展开 $x → $m（内置预处理器）"');
  lines.push('        mv "$x" "$x.sparkbak" 2>/dev/null || true');
  lines.push('      else');
  lines.push('        warn "展开失败：$x"; exit 12');
  lines.push('      fi');
  lines.push('    done');
  lines.push('  else');
  lines.push('    warn "perl 不可用，且找不到内置预处理器"; exit 13');
  lines.push('  fi');
  lines.push('fi');
  lines.push('');
  lines.push("say '开始编译'");
  lines.push(`echo "+ make ${args.join(' ')}"`);
  lines.push('make ' + args.map(q).join(' '));
  lines.push('rc=$?');
  lines.push('end=$(date +%s)');
  lines.push('if [ $rc -ne 0 ]; then echo "[!] 编译失败，退出码 $rc"; exit $rc; fi');
  lines.push('ok "用时 $((end - begin)) 秒"');
  lines.push('', "say '产物'");
  lines.push('ls -lh packages/*.deb .theos/_/ 2>/dev/null | sed "s/^/    /" || true');
  // 产物自检：把 deb 拆开看一眼结构对不对（Rein 的 inject 脚本也是结构化输出）
  lines.push(`for d in packages/*.deb; do`);
  lines.push(`  [ -f "$d" ] || continue`);
  lines.push(`  if command -v dpkg-deb >/dev/null 2>&1; then`);
  lines.push(`    ok "校验 $(basename "$d")"`);
  lines.push(`    dpkg-deb -I "$d" 2>/dev/null | grep -E 'Package:|Version:|Architecture:' | sed 's/^/      /' || true`);
  lines.push(`    dpkg-deb -c "$d" 2>/dev/null | head -5 | sed 's/^/      /' || true`);
  lines.push(`  fi`);
  lines.push(`done`);

  return lines.join('\n');
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
  const s = String(logText);

  // 规则按「越具体越先匹配」排列。
  // 之前 undefined symbol 完全没匹配上、ldid 的 Unknown header magic
  // 也没有对应规则，导致最常见的两类失败给不出任何结论。
  const rules = [
    [/No such file or directory: '?make'?|make: command not found/i,
     '找不到 make：Theos 没装好，或 PATH 里没有 usr/bin。', 'toolchain'],

    [/xcrun: error: unable to find utility "?(clang|ld)"?/i,
     '找不到 clang/ld：Xcode 命令行工具缺失，或工具链没展开。', 'toolchain'],

    [/\bldid: (Unknown header magic|Can only specify)\b/i,
     '签名失败：包里有非 Mach-O 文件（.a 静态库 / 脚本）或符号链接，' +
     'ldid 处理不了。用「工具 → 签名审计」定位具体文件。', 'sign'],

    [/THEOS.*makefiles|makefiles\/common\.mk.*not found/i,
     'THEOS 路径不对：找不到 Theos 的 makefiles 目录。', 'config'],

    [/cannot find sdk|SDKSettings\.json.*not found/i,
     '找不到 SDK：检查 SDK 名称与 theos/sdks 下的目录是否一致。', 'config'],

    // undefined symbol 必须排在 library not found 之前：
    // 链接失败时两者常同时出现，前者信息更具体。
    [/undefined symbol:?\s*(\S+)/i,
     '未定义符号：按日志里的符号名补框架或源文件（如 _OBJC_CLASS_$_Xxx → 加 -framework）。', 'link'],

    [/ld: library not found for -l(\S+)/i,
     '链接不到库：检查 xxx_LIBRARIES 或 .tbd 是否在 SDK / vendor/lib 内。', 'link'],

    [/No rule to make target(?:\s+'?([^'\s]+)'?)?/i,
     '缺少构建规则：Makefile 里的源文件名与实际文件不一致，或分组写错。', 'config'],

    // 先判 logos 相关的具体错误，再判通用 fatal error
    [/logos.*error|%hook|%orig|%new|nil %ctor/i,
     'Logos 预处理失败：检查 .x 里的 %hook / %orig 语法与括号配对。', 'source'],

    [/fatal error: '([^']+)' file not found/i,
     '头文件缺失：确认 SDK 或 vendor/include 里有对应头文件。', 'source'],

    [/error: (expected|use of undeclared|implicit declaration)/i,
     'C/ObjC 语法错误：看第一个 error 行指的位置。', 'source'],

    [/code signature|invalid signature/i,
     '签名失败：确认 ldid 可执行且 entitlements 合法。', 'sign'],

    // libperl 缺失：Rein 移植链的隐藏断点 —— 它带了 perl 薄壳和 104 个
    // .so 扩展，却没带 libperl.dylib。表现是 logos.pl 一行都跑不起来，
    // 报错通常是 "dyld: Library not loaded" 或 "Can't locate ..."。
    // 用 new RegExp 而不是字面量：模式里有单引号（Can't locate），
    // 直接用 // 字面量会和周围的引号打架，导致解析错位。
    [new RegExp("dyld: Library not loaded:.*libperl|Can.t locate (Digest\\/MD5|strict\\\\.pm)|libperl\\\\.dylib", "i"),
     '找不到 libperl.dylib：perl 无法运行，logos.pl 起不来，.x 工程编不了。' +
     '这是运行时打包缺文件（Rein 原包也缺）。' +
     '临时办法：把 %hook 改成纯 .m 写法（用 MSHookMessageEx）。', 'toolchain'],

    [/permission denied/i,
     '权限不足：项目目录要在 /var/mobile 下且可写。', 'permission'],

    [/killed\b|out of memory|Cannot allocate memory/i,
     '进程被杀，多半内存不足：关掉 -j 并行，或改用远程 / CI 构建。', 'resource'],

    [/segmentation fault|Segmentation fault: 11/i,
     '编译器自身崩溃：通常是 OLLVM 与某个源码不兼容，先关混淆试一次。', 'ollvm'],
  ];

  for (const [re, hint, category] of rules) {
    const m2 = s.match(re);
    if (m2) {
      // 把匹配到的具体名字带进提示，便于直接定位
      const detail = m2[1] && m2[1].length < 80 ? `（${m2[1]}）` : '';
      return { hint: hint + detail, category, needle: m2[0] };
    }
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
