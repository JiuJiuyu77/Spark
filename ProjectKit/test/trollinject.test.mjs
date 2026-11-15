import test from 'node:test';
import assert from 'node:assert/strict';

import {
  selectPlugins,
  pickTargetMachO,
  normalizeInstallName,
  planInjection,
  injectionScript,
  parseInsertDylibOutput,
  pickAppBundleFromEntries,
  injectedIpaName,
  describeSource,
} from '../src/trollinject.mjs';

test('从解包目录里挑出插件，忽略系统库', () => {
  const r = selectPlugins([
    'DEBIAN/control',
    'Library/MobileSubstrate/DynamicLibraries/AdBlock.dylib',
    'Library/MobileSubstrate/DynamicLibraries/AdBlock.plist',
    'Library/Application Support/Theme.bundle/Info.plist',
    'Library/Frameworks/Foo.framework/Foo',
    'usr/lib/libswiftCore.dylib',
  ]);
  assert.deepEqual(r.plugins, ['Library/MobileSubstrate/DynamicLibraries/AdBlock.dylib']);
  assert.deepEqual(r.frameworks, ['Library/Frameworks/Foo.framework']);
  assert.deepEqual(r.bundles, ['Library/Application Support/Theme.bundle']);
  assert.equal(r.ignored.length, 1);
  assert.ok(r.ignored[0].includes('libswiftCore'));
});

test('主 Mach-O 选择：优先与 App 同名的可执行文件', () => {
  const entries = [
    'Payload/Demo.app/Demo',
    'Payload/Demo.app/Frameworks/X.framework/X',
    'Payload/Demo.app/PlugIns/N.appex/N',
    'Payload/Demo.app/Info.plist',
  ];
  assert.equal(pickTargetMachO(entries, 'Demo'), 'Payload/Demo.app/Demo');
});

test('主 Mach-O 选择：没有同名时退回第一个候选', () => {
  const entries = ['Payload/A.app/Other', 'Payload/A.app/Info.plist'];
  assert.equal(pickTargetMachO(entries, 'A'), 'Payload/A.app/Other');
  assert.equal(pickTargetMachO(['Payload/A.app/Info.plist'], 'A'), null);
});

test('安装路径规范化：MobileSubstrate 目录', () => {
  assert.equal(
    normalizeInstallName('/var/jb/Library/MobileSubstrate/DynamicLibraries/AdBlock.dylib'),
    '@executable_path/AdBlock.dylib',
  );
});

test('安装路径规范化：framework', () => {
  assert.equal(
    normalizeInstallName('/tmp/x/Foo.framework/Foo'),
    '@executable_path/Frameworks/Foo.framework/Foo',
  );
});

test('安装路径规范化：普通路径只留文件名', () => {
  assert.equal(normalizeInstallName('/private/tmp/a/MyTweak.dylib'), '@executable_path/MyTweak.dylib');
});

test('注入计划包含备份、插入命令与签步骤', () => {
  const plan = planInjection({
    appPath: '/var/containers/Bundle/Application/X/Demo.app',
    executableName: 'Demo',
    plugins: ['/tmp/AdBlock.dylib', '/tmp/Theme.bundle'],
    options: { weak: true, coreTrustBypass: true },
  });
  const titles = plan.steps.map((s) => s.title);
  assert.equal(titles[0], '备份');
  assert.ok(titles.includes('插入加载命令'));
  assert.ok(titles.includes('准备 CydiaSubstrate'));
  assert.ok(titles.includes('CoreTrust 绕过'));
  assert.ok(titles.includes('复制资源包'));
  assert.equal(plan.summary.pluginCount, 2);
  assert.equal(plan.summary.hasSubstrate, true);
});

test('只注入 bundle 时不碰 Mach-O', () => {
  const plan = planInjection({
    appPath: '/tmp/A.app',
    executableName: 'A',
    plugins: ['/tmp/T.bundle'],
  });
  const titles = plan.steps.map((s) => s.title);
  assert.ok(!titles.includes('注入主二进制'));
  assert.equal(plan.summary.hasSubstrate, false);
});

test('注入脚本语法正确且含关键调用', () => {
  const plan = planInjection({
    appPath: '/tmp/Demo.app',
    executableName: 'Demo',
    plugins: ['/tmp/AdBlock.dylib'],
    options: { weak: true, ldid: true },
  });
  const script = injectionScript(plan, {
    insert_dylib: '/usr/bin/insert_dylib',
    ldid: '/usr/bin/ldid',
  });
  assert.ok(script.includes('[ -f "$EXE" ]'));
  assert.ok(script.includes('/usr/bin/insert_dylib'));
  assert.ok(script.includes('--weak'));
  assert.ok(script.includes('@executable_path/AdBlock.dylib'));
  assert.ok(script.includes('cp -R'));
  assert.ok(script.includes('BACKUP="${APP}.sparkbak"'));
});

test('解析 insert_dylib 输出', () => {
  assert.deepEqual(parseInsertDylibOutput('Added LC_LOAD_DYLIB command').added, true);
  assert.equal(parseInsertDylibOutput('Already contains that load command').already, true);
  assert.ok(parseInsertDylibOutput('error: not a Mach-O file').error);
});

test('从条目里找 App bundle', () => {
  assert.equal(pickAppBundleFromEntries(['Payload/X.app/X', 'Payload/X.app/Info.plist']), 'Payload/X.app');
  assert.equal(pickAppBundleFromEntries(['META-INF/x']), null);
});

test('注入后的 IPA 命名', () => {
  assert.equal(injectedIpaName('Demo.ipa'), 'Demo-injected.ipa');
  assert.equal(injectedIpaName('Demo', ['v1']), 'Demo-injected-v1.ipa');
});

test('注入来源说明', () => {
  assert.ok(describeSource('a.deb').includes('Debian'));
  assert.ok(describeSource('a.zip').includes('ZIP'));
  assert.ok(describeSource('x.framework').includes('框架'));
  assert.ok(describeSource('x.dylib').includes('动态库'));
});

test('工具探测能发现同容器的 App helpers', async () => {
  const { searchDirectories } = await import('../src/trolltools.mjs');
  const dirs = searchDirectories({ reinRoot: '/tmp/rein', extraDirs: ['/opt/x'] });
  assert.ok(dirs.includes('/opt/x'));
  assert.ok(dirs.some((d) => d.includes('helpers')));
  assert.equal(new Set(dirs).size, dirs.length, '目录不应重复');
});
