/**
 * 运行时包清单 —— 与 susu123oss/CodexApp-Runtime 的 runtime-manifest.json 对齐。
 *
 * 为什么单独抽出来：App 的「工具链 → 可选组件」页要展示 name / 体积 / 依赖 /
 * 校验值，CLI 与 CI 也要用同一份数据。放 JS 里三端共用，改一处即可。
 *
 * 字段说明：
 *   id            内部标识（对应安装目录名）
 *   name          显示名
 *   components    版本明细（展示用）
 *   archive       下载地址（tar.gz）
 *   sha256        归档校验值（拿不到就留空，只提示不阻断）
 *   size          约等于下载体积（字节）
 *   order         安装顺序（小的先装，依赖在前）
 *   optional      是否可选
 *   pathEntries   解包后要加进 PATH 的子目录
 *   probe         安装后自检：{ executable, arguments, contains }
 *   iosMin        最低 iOS
 */

export const RUNTIME_PROXY_PREFIXES = [
  'https://gh-proxy.org/',
  'https://ghproxy.net/',
];

// 选型依据见 docs/runtime-decision.md：
//  · Theos 用自己的仓库（Rein 本地打包，多一个 SDK 17.0、体积小一半）
//  · 其余全部用 Codex 仓库（Node 24.5.0 有 node-gyp iOS 适配、OLLVM 23.1.1 更新）
const SELF_BASE = 'https://github.com/JiuJiuyu77/Spark-Runtime/releases/download/runtime-v1';
const CODEX_BASE = 'https://github.com/susu123oss/CodexApp-Runtime/releases/download';

export const RUNTIMES = [
  {
    id: 'coretools',
    name: '核心工具集',
    components: { shell: 'usr/bin', libs: 'usr/lib' },
    archive: `${CODEX_BASE}/runtime-core-tools-a7e97567217a/CoreToolsRuntime.tar.gz`,
    file: 'CoreToolsRuntime.tar.gz',
    size: 40 * 1024 * 1024,
    order: 5,
    optional: false,
    pathEntries: ['usr/bin'],
    probe: { executable: 'usr/bin/sh', arguments: ['-c', 'echo ok'], contains: 'ok' },
    iosMin: '15.0',
    detail: '编译链路依赖的基础命令（sh / tar / cp / chmod …）',
  },
  {
    id: 'reverse',
    name: '逆向工具',
    components: { radare2: '6.2.4', 'mt-macho': '2', 'mt-inject-dylib': '1' },
    archive: `${CODEX_BASE}/runtime-reverse-tools-9d3ca9ea3340/ReverseToolsRuntime.tar.gz`,
    file: 'ReverseToolsRuntime.tar.gz',
    size: 60 * 1024 * 1024,
    order: 10,
    optional: true,
    pathEntries: ['bin'],
    probe: { executable: 'bin/rabin2', arguments: ['-h'], contains: 'Usage' },
    iosMin: '15.0',
    detail: 'radare2 / mt-macho / mt-inject-dylib（逆向、注入都用它）',
  },
  {
    id: 'node',
    name: 'Node.js 24.5.0',
    components: { node: '24.5.0', npm: '11.5.1', corepack: '0.34.0' },
    archive: `${CODEX_BASE}/runtime-node-24.5.0-e3a6c25fac33/NodeRuntime.tar.gz`,
    file: 'NodeRuntime.tar.gz',
    size: 28 * 1024 * 1024,
    order: 15,
    optional: true,
    pathEntries: ['bin'],
    probe: { executable: 'bin/node', arguments: ['-e', 'console.log("ok "+process.version)'], contains: 'ok' },
    iosMin: '15.0',
    detail: 'Node 24.5.0 + npm + corepack（pnpm / yarn 走 corepack）',
  },
  {
    id: 'buildtools',
    name: '构建工具',
    components: { cmake: '3.27.9', ninja: '1.11.1' },
    archive: `${CODEX_BASE}/runtime-build-tools-3.27.9-fb0f29cea7b2/BuildToolsRuntime.tar.gz`,
    file: 'BuildToolsRuntime.tar.gz',
    size: 8 * 1024 * 1024,
    order: 15,
    optional: true,
    pathEntries: ['bin'],
    probe: { executable: 'bin/ninja', arguments: ['--version'], contains: '1.11' },
    iosMin: '15.0',
    detail: 'CMake + Ninja（C/C++ 工程）',
  },
  {
    id: 'python',
    name: 'Python 3.13',
    components: { python: '3.13.14' },
    archive: `${CODEX_BASE}/runtime-python-3.13.14-3c834a2c8964/PythonRuntime.tar.gz`,
    file: 'PythonRuntime.tar.gz',
    size: 10 * 1024 * 1024,
    order: 20,
    optional: true,
    pathEntries: ['bin'],
    probe: { executable: 'bin/python3', arguments: ['-c', 'print("py ok")'], contains: 'py ok' },
    iosMin: '15.0',
    detail: 'Python 3.13.14（Theos 脚本工具链会用到）',
  },
  {
    id: 'theos',
    name: 'Theos 完整版',
    components: { theos: 'Rein 本地', sdks: 'iPhoneOS16.5 + 17.0' },
    archive: `${SELF_BASE}/theos/TheosRuntime.tar.gz`,
    file: 'TheosRuntime.tar.gz',
    size: 114 * 1024 * 1024,
    order: 25,
    optional: true,
    pathEntries: ['theos/bin'],
    probe: { executable: 'theos/bin/logos.pl', arguments: [], contains: '' },
    iosMin: '15.0',
    detail: '完整 Theos（含 16.5 / 17.0 两个 SDK），内置版不够用时安装',
  },
  {
    id: 'ollvm',
    name: 'OLLVM 混淆',
    components: { llvm: '23.1.1', passes: 'indbr/icall/indgv/cse/fla/cie/cfe' },
    archive: `${CODEX_BASE}/runtime-ollvm-23.1.1-e54f2878240e/OLLVMRuntime.tar.gz`,
    file: 'OLLVMRuntime.tar.gz',
    size: 35 * 1024 * 1024,
    order: 30,
    optional: true,
    pathEntries: ['bin'],
    probe: { executable: 'bin/clang', arguments: ['--version'], contains: 'clang version' },
    iosMin: '15.0',
    detail: 'Arkari LLVM 23.1.1，7 个 pass（arm64e 已验证）',
  },
];

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

/** 安装子目录名（与 Spark-Runtime 的包 id 一致） */
export function sdkSubdirFor(runtimeId) {
  return runtimeId;
}
