#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# 从 runtime-manifest.json 生成 ObjC 兜底数组。
# 保证 bundle 里的 JSON 与编译进二进制的兜底永远一致。
import io, json

JSON_PATH = 'Native/Resources/runtime-manifest.json'
OUT_PATH = 'Native/ObjC/SPRuntimeManifestFallback.h'


def objc_str(s):
    return '@"' + str(s).replace('\\', '\\\\').replace('"', '\\"') + '"'


def main():
    with io.open(JSON_PATH, encoding='utf-8') as f:
        data = json.load(f)

    L = []
    L.append('//')
    L.append('//  SPRuntimeManifestFallback.h')
    L.append('//  **自动生成，不要手改**')
    L.append('//')
    L.append('//  由 scripts/gen-runtime-manifest.py 从')
    L.append('//  Native/Resources/runtime-manifest.json 生成。')
    L.append('//  改数据请改 JSON，然后跑：')
    L.append('//      python3 scripts/gen-runtime-manifest.py')
    L.append('//')
    L.append('')
    L.append('#import <Foundation/Foundation.h>')
    L.append('')
    L.append('/// bundle 里没有 runtime-manifest.json 时用的兜底（内容与 JSON 完全一致）')
    L.append('static NSArray<NSDictionary *> *SPRuntimeManifestFallback(void) {')
    L.append('    return @[')

    for c in data['components']:
        probe = c.get('probe') or {}
        parts = []
        parts.append('@{@"id": %s' % objc_str(c['id']))
        parts.append('@"name": %s' % objc_str(c['name']))
        parts.append('@"detail": %s' % objc_str(c.get('detail', '')))
        parts.append('@"symbol": %s' % objc_str(c.get('symbol', 'shippingbox')))
        parts.append('@"archive": %s' % objc_str(c['archive']))
        parts.append('@"size": @(%d)' % int(c.get('bytes', 0)))
        parts.append('@"order": @(%d)' % int(c.get('order', 0)))
        parts.append('@"optional": @(%s)' % ('YES' if c.get('optional') else 'NO'))
        parts.append('@"probe": %s' % objc_str(probe.get('executable', '')))
        entries = c.get('pathEntries') or []
        ent = ', '.join(objc_str(e) for e in entries) if entries else ''
        parts.append('@"pathEntries": @[%s]' % ent)
        if c.get('sdkName'):
            parts.append('@"sdkName": %s' % objc_str(c['sdkName']))
        L.append('        ' + ', '.join(parts) + '},')

    L.append('    ];')
    L.append('}')
    L.append('')

    with io.open(OUT_PATH, 'w', encoding='utf-8') as f:
        f.write('\n'.join(L))
    print('生成 %s（%d 个组件）' % (OUT_PATH, len(data['components'])))


if __name__ == '__main__':
    main()
