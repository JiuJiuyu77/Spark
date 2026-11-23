/**
 * mcp-tools.mjs —— Workbench 的 MCP 工具定义与处理器（纯逻辑，零依赖）
 *
 * MCP = Model Context Protocol。把 Workbench 的能力暴露成一组工具，
 * 任何 MCP 客户端（Claude Desktop、Cursor、Zed、自己写的 agent）
 * 都能直接调用：
 *   · 探测工具链        spark_doctor
 *   · 列项目 / 读文件    spark_projects / spark_read_file
 *   · 生成构建脚本       spark_build_script
 *   · 生成注入计划       spark_inject_plan
 *   · 逆向分析           spark_analyze
 *
 * 这里刻意只做「纯函数 + 注入式依赖」：
 *   文件系统、子进程都通过 deps 传入，所以既能跑在 Node 里（stdio server），
 *   也能跑在 Cloudflare Worker（HTTP/SSE）里，还能在测试里用假实现。
 *
 * 协议版本：2024-11-05（tools 能力）
 */

import {
  buildScript,
  defaultOptions,
  detectProject,
  diagnose,
  makeArguments,
  makeEnvironment,
  OLLVM_PASSES,
  OBFUSCATION_PRESETS,
  pickSDK,
} from '../../ShareKit/src/model.js';
import { planInjection, injectionScript, selectPlugins } from './trollinject.mjs';
import { detectTools, summarizeTools, remediesFor } from './trolltools.mjs';

export const MCP_PROTOCOL_VERSION = '2024-11-05';
export const SERVER_INFO = { name: 'spark', version: '1.1.0' };

/** 所有工具的 JSON Schema 定义（给 tools/list 用） */
export const TOOL_DEFINITIONS = [
  {
    name: 'spark_doctor',
    description: '探测 Workbench 的编译能力：Theos、iPhoneOS SDK、OLLVM、逆向工具、巨魔注入工具链。返回哪些可用、哪些缺失以及补救建议。',
    inputSchema: {
      type: 'object',
      properties: {
        reinRoot: { type: 'string', description: 'Rein 根目录，默认 /var/mobile/Documents/Rein' },
      },
    },
  },
  {
    name: 'spark_projects',
    description: '列出目录下的 Theos / Node 项目，识别类型（tweak / application / library / tool / bundle / node）。',
    inputSchema: {
      type: 'object',
      properties: {
        root: { type: 'string', description: '要扫描的目录' },
        depth: { type: 'number', description: '递归深度，默认 1' },
      },
      required: ['root'],
    },
  },
  {
    name: 'spark_read_file',
    description: '读取一个文本文件的内容（带行数限制，避免把大文件塞进上下文）。',
    inputSchema: {
      type: 'object',
      properties: {
        path: { type: 'string' },
        maxLines: { type: 'number', description: '默认 400 行' },
      },
      required: ['path'],
    },
  },
  {
    name: 'spark_build_script',
    description: '为一个 Theos 项目生成完整的构建 shell 脚本（含工具链自检、make 参数、OLLVM flags、产物收集），可直接执行或粘贴到终端。',
    inputSchema: {
      type: 'object',
      properties: {
        path: { type: 'string', description: '项目目录' },
        debug: { type: 'boolean', description: '是否 Debug 构建，默认 true' },
        arch: { type: 'string', enum: ['arm64', 'arm64e', 'both'] },
        format: { type: 'string', enum: ['deb', 'rootless', 'app', 'tipa'] },
        obfuscation: {
          type: 'string',
          enum: ['none', 'light', 'balanced', 'strong'],
          description: 'OLLVM 混淆强度：light=indbr+cse，balanced=+icall，strong=全部 5 个 pass',
        },
        clean: { type: 'boolean', description: '构建前先 make clean' },
      },
      required: ['path'],
    },
  },
  {
    name: 'spark_inject_plan',
    description: '为「巨魔注入」生成计划：把一个或多个 dylib/framework/bundle 注入到 .app 里，列出每一步会做什么（不执行）。',
    inputSchema: {
      type: 'object',
      properties: {
        appPath: { type: 'string', description: '目标 .app 绝对路径' },
        executableName: { type: 'string', description: 'App 主二进制名，默认取 .app 名' },
        plugins: {
          type: 'array',
          items: { type: 'string' },
          description: '要注入的 dylib / framework / bundle 路径',
        },
        weak: { type: 'boolean', description: '用 LC_LOAD_WEAK_DYLIB（加密 App 必须）' },
        script: { type: 'boolean', description: '是否同时返回可执行的 shell 脚本' },
      },
      required: ['appPath', 'plugins'],
    },
  },
  {
    name: 'spark_analyze',
    description: '对 Mach-O 二进制做基础分析（架构、符号、字符串、依赖）。需要设备上装有 radare2；返回结构化摘要。',
    inputSchema: {
      type: 'object',
      properties: {
        path: { type: 'string', description: '二进制路径' },
        mode: { type: 'string', enum: ['info', 'symbols', 'strings', 'imports', 'sections'] },
        limit: { type: 'number', description: '最多返回多少行，默认 80' },
      },
      required: ['path'],
    },
  },
];

/** 把错误包成 MCP 的 tool result */
function errorResult(message) {
  return { content: [{ type: 'text', text: `错误：${message}` }], isError: true };
}

function textResult(text, extra = {}) {
  return { content: [{ type: 'text', text }], ...extra };
}

/**
 * 校验参数（MCP 服务端应该自己校验，别指望客户端）。
 * 只做「必填 + 类型」这一层，够用且不会过度限制。
 */
function requireString(args, key) {
  const v = args?.[key];
  if (typeof v !== 'string' || !v.trim()) throw new Error(`缺少参数 ${key}`);
  return v;
}

/**
 * 调用一个工具。
 * @param {string} name 工具名
 * @param {object} args 参数
 * @param {object} deps 依赖注入：
 *   { readdir(path)->string[], stat(path)->{isDir,size,mtime}, readFile(path)->string,
 *     exists(path)->boolean, run(cmd,args)->{code,stdout,stderr}, env: {...} }
 */
export async function callTool(name, args = {}, deps = {}) {
  const {
    readdir = () => [],
    readFile = () => '',
    exists = () => false,
    run = async () => ({ code: 127, stdout: '', stderr: '未提供 run 实现' }),
    pathJoin = (...p) => p.join('/'),
    env = {},
  } = deps;

  try {
    switch (name) {
      case 'spark_doctor': {
        const reinRoot = args.reinRoot || env.REIN_ROOT || '/var/mobile/Documents/Rein';
        const tools = detectTools({ reinRoot, extraDirs: [pathJoin(reinRoot, 'tools/ollvm/bin')] });
        const lines = [
          `Rein 根目录: ${reinRoot}`,
          `注入工具链: ${summarizeTools(tools)}`,
          `注入可用: ${tools.ready ? '是' : '否'}`,
        ];
        // SDK 清单（若有）
        const sdks = readdir(pathJoin(reinRoot, 'sdks-store')).filter((n) => n.endsWith('.sdk'));
        if (sdks.length) lines.push(`可用 SDK: ${sdks.join(', ')}`);
        const theosBin = pathJoin(reinRoot, 'tools/theos-full/bin/logos.pl');
        lines.push(`Theos(Logos): ${exists(theosBin) ? '可用' : '未找到'}`);
        const ollvm = pathJoin(reinRoot, 'tools/ollvm/bin/clang');
        lines.push(`OLLVM clang: ${exists(ollvm) ? '可用' : '未找到'}`);
        const remedies = remediesFor(tools);
        if (remedies.length) lines.push('', '建议：', ...remedies.map((r) => `- ${r}`));
        return textResult(lines.join('\n'));
      }

      case 'spark_projects': {
        const root = requireString(args, 'root');
        if (!exists(root)) return errorResult(`目录不存在：${root}`);
        const depth = Math.max(0, Math.min(4, Number(args.depth ?? 1)));
        const out = [];
        const walk = (dir, level) => {
          if (level > depth) return;
          for (const name of readdir(dir)) {
            if (name.startsWith('.')) continue;
            const full = pathJoin(dir, name);
            const io = {
              hasFile: (rel) => exists(pathJoin(full, rel)),
              readFile: (rel) => readFile(pathJoin(full, rel)),
            };
            const info = detectProject(io);
            if (info.isTheos || info.kind !== 'unknown') {
              out.push(
                `- ${full}  [${info.kind}]` +
                  (info.packageId ? ` ${info.packageId}` : '') +
                  (info.version ? ` v${info.version}` : '') +
                  (info.executable ? ` exe=${info.executable}` : ''),
              );
            } else if (level < depth) {
              walk(full, level + 1);
            }
          }
        };
        walk(root, 0);
        if (!out.length) return textResult(`在 ${root} 下没找到项目（深度 ${depth}）`);
        return textResult(`找到 ${out.length} 个项目：\n${out.join('\n')}`);
      }

      case 'spark_read_file': {
        const path = requireString(args, 'path');
        if (!exists(path)) return errorResult(`文件不存在：${path}`);
        const maxLines = Math.max(1, Math.min(2000, Number(args.maxLines ?? 400)));
        const content = readFile(path);
        if (typeof content !== 'string') return errorResult('读取失败（可能是二进制文件）');
        const lines = content.split('\n');
        const shown = lines.slice(0, maxLines).join('\n');
        const tail =
          lines.length > maxLines ? `\n\n…（共 ${lines.length} 行，已截断到 ${maxLines} 行）` : '';
        return textResult(shown + tail);
      }

      case 'spark_build_script': {
        const dir = requireString(args, 'path');
        if (!exists(dir)) return errorResult(`目录不存在：${dir}`);
        const io = {
          hasFile: (rel) => exists(pathJoin(dir, rel)),
          readFile: (rel) => readFile(pathJoin(dir, rel)),
        };
        const info = detectProject(io);
        if (!info.isTheos) return errorResult(`${dir} 不是 Theos 项目（没有 Makefile）`);

        const options = {
          ...defaultOptions(),
          debug: args.debug !== false,
          arch: args.arch || 'arm64',
          format: args.format || 'rootless',
          clean: !!args.clean,
          ollvm: !!args.obfuscation && args.obfuscation !== 'none',
          obfuscation: args.obfuscation || 'none',
        };
        const reinRoot = env.REIN_ROOT || '/var/mobile/Documents/Rein';
        const theos = [pathJoin(reinRoot, 'tools/theos-full'), pathJoin(reinRoot, 'tools/theos-local')].find(exists);
        const sdkDir = theos ? pathJoin(theos, 'sdks') : pathJoin(reinRoot, 'sdks-store');
        const sdkName = pickSDK(readdir(sdkDir).filter((n) => n.endsWith('.sdk')), '17.0');
        const profile = {
          theos: theos || '/opt/theos',
          sdk: sdkName ? pathJoin(sdkDir, sdkName) : null,
          ollvmRoot: exists(pathJoin(reinRoot, 'tools/ollvm/bin/clang')) ? pathJoin(reinRoot, 'tools/ollvm') : null,
        };
        const script = buildScript({ path: dir }, options, profile);
        const header = [
          `# 项目：${dir} [${info.kind}]${info.packageId ? ` ${info.packageId}` : ''}`,
          `# make: make ${makeArguments(options).join(' ')}`,
          `# 关键环境：${Object.entries(makeEnvironment(options))
            .filter(([k]) => ['ARCHS', 'THEOS_PACKAGE_SCHEME', 'DEBUG', 'ADDITIONAL_CCFLAGS'].includes(k))
            .map(([k, v]) => `${k}=${String(v).slice(0, 60)}`)
            .join(' ')}`,
          '',
        ].join('\n');
        return textResult(header + script);
      }

      case 'spark_inject_plan': {
        const appPath = requireString(args, 'appPath');
        const plugins = Array.isArray(args.plugins) ? args.plugins : [];
        if (!plugins.length) return errorResult('plugins 不能为空');
        const executableName =
          args.executableName || String(appPath).split('/').pop().replace(/\.app$/, '');
        const options = { weak: args.weak !== false, coreTrustBypass: true, ldid: true };
        const plan = planInjection({ appPath, executableName, plugins, options });
        const lines = [
          `目标：${appPath}（${executableName}）`,
          `插件：${plugins.length} 个`,
          '',
          ...plan.steps.map((s, i) => `${String(i + 1).padStart(2, ' ')}. ${s.title}：${s.detail}`),
        ];
        if (args.script) {
          lines.push('', '```sh', injectionScript(plan, detectTools({}).found), '```');
        }
        return textResult(lines.join('\n'));
      }

      case 'spark_analyze': {
        const path = requireString(args, 'path');
        if (!exists(path)) return errorResult(`文件不存在：${path}`);
        const mode = args.mode || 'info';
        const limit = Math.max(1, Math.min(500, Number(args.limit ?? 80)));
        const flag = { info: ['-I'], symbols: ['-s'], strings: ['-zz'], imports: ['-i'], sections: ['-S'] }[mode] || ['-I'];
        const r = await run('rabin2', [...flag, path]);
        if (r.code !== 0) {
          return errorResult(
            `rabin2 执行失败（exit ${r.code}）：${(r.stderr || '').slice(0, 300)}\n` +
              '请确认设备上装了 Rein 的逆向工具（tools/reverse/bin/rabin2）。',
          );
        }
        const text = String(r.stdout || '').split('\n').slice(0, limit).join('\n');
        return textResult(`# ${mode}: ${path}\n${text}`);
      }

      default:
        return errorResult(`未知工具：${name}`);
    }
  } catch (err) {
    return errorResult(err && err.message ? err.message : String(err));
  }
}

/** 给 MCP 客户端看的帮助文本（resources 里会用到） */
export function describeCapabilities() {
  const passes = Object.entries(OLLVM_PASSES)
    .map(([id, d]) => `  ${id.padEnd(6)} ${d.title}`)
    .join('\n');
  const presets = Object.entries(OBFUSCATION_PRESETS)
    .map(([k, v]) => `  ${k.padEnd(9)} ${v.join(', ') || '（无）'}`)
    .join('\n');
  return `Workbench MCP 服务（${SERVER_INFO.name} v${SERVER_INFO.version}）

工具：
${TOOL_DEFINITIONS.map((t) => `  ${t.name.padEnd(20)} ${t.description.split('\n')[0]}`).join('\n')}

OLLVM passes：
${passes}

混淆预设：
${presets}

诊断规则示例：${diagnose('ld: library not found for -lfoo')?.hint || '（无）'}
`;
}
