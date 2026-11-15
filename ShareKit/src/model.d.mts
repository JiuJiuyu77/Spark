/**
 * build.d.mts —— 给 TypeScript 用的类型声明（手写，保持与 model.js 同步）。
 * 不引入构建步骤：Worker 和 CI 都可以直接 JS 引用。
 */

export type ProjectKindValue =
  | 'tweak' | 'application' | 'library' | 'tool' | 'bundle' | 'node' | 'script' | 'unknown';

export interface BuildOptions {
  arch: 'arm64' | 'arm64e' | 'both';
  format: 'deb' | 'rootless' | 'app' | 'tipa';
  debug: boolean;
  clean: boolean;
  finalize: boolean;
  ldid: boolean;
  strip: boolean;
  ollvm: boolean;
  obfuscation: 'none' | 'light' | 'balanced' | 'strong' | 'custom';
  passes: string[];
  parallel: boolean;
  jobs: number;
  extraArgs: string;
  extraEnv: string;
  version: string;
}

export interface ProjectIO {
  hasFile(rel: string): boolean;
  readFile(rel: string): string | null;
}

export interface ProjectInfo {
  isTheos: boolean;
  kind: ProjectKindValue;
  executable: string | null;
  packageId: string | null;
  version: string | null;
  archs: string | null;
  target: string | null;
  name?: string;
}

export interface Profile {
  env?: Record<string, string>;
  pathPrefix?: string;
  theos?: string;
  sdk?: string;
  ollvmRoot?: string;
}

export const ProjectKind: Record<string, ProjectKindValue>;
export const PackageFormat: Record<string, string>;
export const Arch: Record<string, string>;
export const Obfuscation: Record<string, string>;
export const OLLVM_PASSES: Record<string, { title: string; flags: string[] }>;
export const OBFUSCATION_PRESETS: Record<string, string[]>;

export function defaultOptions(): BuildOptions;
export function passesForObfuscation(level: string, custom?: string[]): string[];
export function flagsForPasses(passes?: string[]): string[];
export function parseMakefileNames(makefileText?: string): Record<string, string>;
export function parseControl(controlText?: string): Record<string, string>;
export function detectProject(io: ProjectIO): ProjectInfo;
export function makeEnvironment(options?: Partial<BuildOptions>): Record<string, string>;
export function makeArguments(options?: Partial<BuildOptions>): string[];
export function buildScript(project: { path?: string }, options?: Partial<BuildOptions>, profile?: Profile): string;
export function shellQuote(s: unknown): string;
export function diagnose(logText?: string): { hint: string; category: string; needle: string } | null;
export function compareVersions(a: string, b: string): -1 | 0 | 1;
export function pickSDK(sdkNames?: string[], prefer?: string): string | null;
