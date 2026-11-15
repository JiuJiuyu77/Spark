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

const BASE = 'https://github.com/susu123oss/CodexApp-Runtime/releases/download';

export const RUNTIMES = [
  {
    id: 'core_tools',
    name: '核心工具集',
    components: { shell: 'busybox-style', arch: 'arm64' },
    archive: `${BASE}/runtime-core-tools-a7e97567217a/CoreToolsRuntime.tar.gz`,
    sha256: 'a7e97567217a',
    size: 9.5 * 1024 * 1024,
    order: 5,
    optional: false,
    pathEntries: ['bin'],
    probe: { executable: 'bin/sh', arguments: ['-c', 'echo ok'], contains: 'ok' },
    iosMin: '15.0',
    detail: '编译链路依赖的基础命令（sh / tar / cp / chmod …）',
  },
  {
    id: 'node',
    name: 'Node.js',
    components: { node: '24.5.0', npm: '11.5.1', corepack: '0.34.0', 'node-gyp': '11.2.0' },
    archive: `${BASE}/runtime-node-24.5.0-e3a6c25fac33/NodeRuntime.tar.gz`,
    sha256: 'e3a6c25fac33',
    size: 28.1 * 1024 * 1024,
    order: 15,
    optional: true,
    pathEntries: ['bin'],
    probe: {
      executable: 'bin/node',
      arguments: ['-e', 'console.log("codex-node-runtime-ok "+process.version)'],
      contains: 'codex-node-runtime-ok',
    },
    iosMin: '15.0',
    detail: 'Node 24.5.0 + npm 11.5.1 + corepack（pnpm / yarn 走 corepack）',
  },
  {
    id: 'python',
    name: 'Python',
    components: { python: '3.13.14' },
    archive: `${BASE}/runtime-python-3.13.14-3c834a2c8964/PythonRuntime.tar.gz`,
    sha256: '3c834a2c8964',
    size: 10.1 * 1024 * 1024,
    order: 20,
    optional: true,
    pathEntries: ['bin'],
    probe: { executable: 'bin/python3', arguments: ['-c', 'print("py ok")'], contains: 'py ok' },
    iosMin: '15.0',
    detail: 'Python 3.13.14（Theos 的脚本工具链会用到）',
  },
  {
    id: 'reverse_tools',
    name: '逆向工具',
    components: { radare2: '6.2.4', 'mt-macho': '2', 'mt-inject-dylib': '1' },
    archive: `${BASE}/runtime-reverse-tools-9d3ca9ea3340/ReverseToolsRuntime.tar.gz`,
    sha256: '9d3ca9ea3340',
    size: 16.6 * 1024 * 1024,
    order: 10,
    optional: true,
    pathEntries: ['bin'],
    probe: { executable: 'bin/rabin2', arguments: ['-h'], contains: 'Usage' },
    iosMin: '15.0',
    detail: 'radare2 / mt-macho / mt-inject-dylib（逆向、注入都用它）',
  },
  {
    id: 'ollvm',
    name: 'OLLVM 混淆',
    components: { llvm: '23.1.1', passes: 'indbr/icall/indgv/cse/cff' },
    archive: `${BASE}/runtime-ollvm-23.1.1-e54f2878240e/OLLVMRuntime.tar.gz`,
    sha256: 'e54f2878240e',
    size: 34.7 * 1024 * 1024,
    order: 30,
    optional: true,
    pathEntries: ['bin'],
    probe: { executable: 'bin/clang', arguments: ['--version'], contains: 'clang version' },
    iosMin: '15.0',
    detail: 'Arkari OLLVM 23.1.1，5 个混淆 pass',
  },
  {
    id: 'build_tools',
    name: '构建工具',
    components: { cmake: '3.27.9', ninja: '1.11.1' },
    archive: `${BASE}/runtime-build-tools-3.27.9-fb0f29cea7b2/BuildToolsRuntime.tar.gz`,
    sha256: 'fb0f29cea7b2',
    size: 7.2 * 1024 * 1024,
    order: 15,
    optional: true,
    pathEntries: ['bin'],
    probe: { executable: 'bin/ninja', arguments: ['--version'], contains: '1.11.1' },
    iosMin: '15.0',
    detail: 'CMake + Ninja（C/C++ 工程）',
  },
  {
    id: 'theos',
    name: 'Theos 完整版',
    components: { theos: 'latest', makefiles: 'included', logos: 'perl' },
    archive: `${BASE}/runtime-theos-787697a97c96/TheosRuntime.tar.gz`,
    sha256: '787697a97c96',
    size: 214.1 * 1024 * 1024,
    order: 20,
    optional: true,
    pathEntries: ['bin'],
    probe: { executable: 'bin/logos.pl', arguments: [], contains: '' },
    iosMin: '15.0',
    detail: '完整 Theos（内置精简版不够用时再装；不含 SDK）',
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

/** node 是否满足最低版本（用于「项目内嵌 Node 版本」判断） */
export function sdkSubdirFor(runtimeId) {
  return runtimeId === 'node' ? 'node' : runtimeId;
}
