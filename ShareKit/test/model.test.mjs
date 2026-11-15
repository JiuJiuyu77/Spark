import test from 'node:test';
import assert from 'node:assert/strict';

import {
  detectProject,
  parseMakefileNames,
  parseControl,
  makeEnvironment,
  makeArguments,
  buildScript,
  shellQuote,
  diagnose,
  pickSDK,
  compareVersions,
  flagsForPasses,
  passesForObfuscation,
  defaultOptions,
  ProjectKind,
} from '../src/model.js';

const ioFrom = (files) => ({
  hasFile: (rel) => Object.prototype.hasOwnProperty.call(files, rel),
  readFile: (rel) => files[rel] ?? null,
});

test('识别 tweak 项目', () => {
  const info = detectProject(
    ioFrom({
      Makefile: 'TWEAK_NAME = MyTweak\nMyTweak_FILES = Tweak.x\n',
      control: 'Package: com.example.mytweak\nVersion: 1.2.3\n',
    }),
  );
  assert.equal(info.isTheos, true);
  assert.equal(info.kind, ProjectKind.TWEAK);
  assert.equal(info.executable, 'MyTweak');
  assert.equal(info.packageId, 'com.example.mytweak');
  assert.equal(info.version, '1.2.3');
});

test('识别 application 项目', () => {
  const info = detectProject(ioFrom({ Makefile: 'APPLICATION_NAME = DemoApp\n' }));
  assert.equal(info.kind, ProjectKind.APPLICATION);
  assert.equal(info.executable, 'DemoApp');
});

test('Makefile 里的 $(VAR) 引用不会被误认成名字', () => {
  const names = parseMakefileNames('TWEAK_NAME = $(BUNDLE_ID)\n');
  assert.equal(names.TWEAK_NAME, undefined);
});

test('注释行不参与解析', () => {
  const names = parseMakefileNames('# TWEAK_NAME = Nope\nTWEAK_NAME = Real\n');
  assert.equal(names.TWEAK_NAME, 'Real');
});

test('control 解析', () => {
  const c = parseControl('Package: a.b\n Name: Hi\nVersion: 2.0\nDepends: firmware (>= 15.0)\n');
  assert.equal(c.package, 'a.b');
  assert.equal(c.name, 'Hi');
  assert.equal(c.version, '2.0');
});

test('node 项目识别', () => {
  const info = detectProject(ioFrom({ 'package.json': JSON.stringify({ name: 'x', version: '0.1.0' }) }));
  assert.equal(info.kind, ProjectKind.NODE);
  assert.equal(info.version, '0.1.0');
});

test('make 环境变量：架构与包格式', () => {
  const env = makeEnvironment({ arch: 'both', format: 'rootless', debug: false, strip: true });
  assert.equal(env.ARCHS, 'arm64 arm64e');
  assert.equal(env.THEOS_PACKAGE_SCHEME, 'rootless');
  assert.equal(env.DEBUG, '0');
  assert.equal(env.OPTFLAG, '-O2');
  assert.equal(env.STRIP, '1');
});

test('make 环境变量：OLLVM passes 展开', () => {
  const env = makeEnvironment({ ollvm: true, obfuscation: 'balanced' });
  assert.ok(env.ADDITIONAL_CCFLAGS.includes('--irobf-indbr'));
  assert.ok(env.ADDITIONAL_CCFLAGS.includes('--irobf-icall'));
  assert.ok(env.ADDITIONAL_CCFLAGS.includes('--irobf-cse'));
  assert.equal(env.ADDITIONAL_CPPFLAGS, undefined, '旧变量名会触发 Theos deprecate 警告');
  assert.equal(env.SP_OLLVM_PASSES, 'indbr,icall,cse');
});

test('extraEnv 覆盖生效', () => {
  const env = makeEnvironment({ extraEnv: 'FOO=bar\nBAZ=1\n' });
  assert.equal(env.FOO, 'bar');
  assert.equal(env.BAZ, '1');
});

test('make 参数：clean + package + FINALPACKAGE', () => {
  const args = makeArguments({ clean: true, finalize: true, format: 'deb', parallel: false });
  assert.deepEqual(args, ['clean', 'package', 'FINALPACKAGE=1']);
});

test('包格式 app 时不 package', () => {
  const args = makeArguments({ format: 'app', finalize: true, parallel: false });
  assert.deepEqual(args, ['all']);
});

test('shellQuote 处理空格与引号', () => {
  assert.equal(shellQuote('abc'), 'abc');
  assert.equal(shellQuote('/tmp/a b'), "'/tmp/a b'");
  assert.equal(shellQuote("it's"), "'it'\\''s'");
  assert.equal(shellQuote(''), "''");
});

test('buildScript 包含关键片段', () => {
  const s = buildScript({ path: '/tmp/proj' }, { ollvm: true, obfuscation: 'light' }, {
    theos: '/opt/theos',
    sdk: '/opt/theos/sdks/iPhoneOS16.5.sdk',
  });
  assert.ok(s.includes('export THEOS=/opt/theos'));
  assert.ok(s.includes('cd /tmp/proj'));
  assert.ok(s.includes('make package'));
  assert.ok(s.includes('--irobf-indbr'));
  assert.ok(s.includes('set -o pipefail'));
});

test('诊断：常见错误', () => {
  assert.equal(diagnose('ld: library not found for -lfoo').category, 'link');
  assert.equal(diagnose("fatal error: 'UIKit/UIKit.h' file not found").category, 'source');
  assert.equal(diagnose('Killed').category, 'resource');
  assert.equal(diagnose('all good'), null);
});

test('版本比较与 SDK 选择', () => {
  assert.equal(compareVersions('16.5', '17.0'), -1);
  assert.equal(compareVersions('17.0', '17.0'), 0);
  const names = ['iPhoneOS16.5.sdk', 'iPhoneOS17.0.sdk', 'iPhoneOS26.5.sdk'];
  assert.equal(pickSDK(names, '17.0'), 'iPhoneOS17.0.sdk');
  assert.equal(pickSDK(names, '16.0'), 'iPhoneOS16.5.sdk');
  assert.equal(pickSDK([]), null);
});

test('passes 预设与 flags 一致', () => {
  assert.deepEqual(passesForObfuscation('strong'), ['indbr', 'icall', 'indgv', 'cse', 'cff']);
  assert.deepEqual(passesForObfuscation('custom', ['cff']), ['cff']);
  assert.deepEqual(flagsForPasses(['cff']), ['-mllvm', '-irobf', '-mllvm', '--irobf-cff']);
});

test('defaultOptions 稳定', () => {
  const a = defaultOptions();
  assert.equal(a.format, 'rootless');
  assert.equal(a.debug, true);
  assert.ok(Array.isArray(a.passes));
});
