#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# 校验运行时清单三处同源：
#   1. Native/Resources/runtime-manifest.json（唯一真相）
#   2. Native/ObjC/SPRuntimeManifestFallback.h（自动生成，必须与 JSON 一致）
#   3. ProjectKit/src/runtimes.mjs（运行时读取，不能自己写死数据）
import io, json, re, sys

JSON_PATH = 'Native/Resources/runtime-manifest.json'
FALLBACK = 'Native/ObjC/SPRuntimeManifestFallback.h'
MJS = 'ProjectKit/src/runtimes.mjs'


def main():
    problems = []

    try:
        with io.open(JSON_PATH, encoding='utf-8') as f:
            data = json.load(f)
    except Exception as e:
        print('无法解析 %s: %s' % (JSON_PATH, e))
        sys.exit(1)

    comps = data.get('components') or []
    if not comps:
        problems.append('%s 里没有 components' % JSON_PATH)

    ids = [c.get('id') for c in comps]

    # 必备字段
    for c in comps:
        for k in ('id', 'name', 'archive', 'bytes', 'order', 'pathEntries', 'probe'):
            if k not in c:
                problems.append('组件 %s 缺字段 %s' % (c.get('id'), k))
        if c.get('archive') and not c['archive'].startswith('https://'):
            problems.append('组件 %s 的 archive 不是 https' % c.get('id'))

    # 兜底头文件必须与 JSON 一致
    try:
        fb = io.open(FALLBACK, encoding='utf-8').read()
    except OSError:
        fb = ''
        problems.append('缺少 %s（跑 scripts/gen-runtime-manifest.py）' % FALLBACK)

    if fb:
        fb_ids = re.findall(r'@"id":\s*@"([^"]+)"', fb)
        if fb_ids != ids:
            problems.append(
                '%s 的 id 序列与 JSON 不一致\n  JSON: %s\n  兜底: %s'
                % (FALLBACK, ids, fb_ids))
        # 体积必须逐个对得上
        for c in comps:
            pat = r'@"id":\s*@"%s".*?@"size":\s*@\((\d+)\)' % re.escape(c['id'])
            m = re.search(pat, fb, re.S)
            if not m:
                problems.append('兜底里找不到 %s 的 size' % c['id'])
            elif int(m.group(1)) != int(c.get('bytes', 0)):
                problems.append(
                    '组件 %s 体积不一致：JSON=%s 兜底=%s'
                    % (c['id'], c.get('bytes'), m.group(1)))

    # runtimes.mjs 不能自己写死数据
    try:
        mjs = io.open(MJS, encoding='utf-8').read()
    except OSError:
        mjs = ''
        problems.append('缺少 %s' % MJS)

    if mjs:
        if 'runtime-manifest.json' not in mjs:
            problems.append('%s 没有引用 runtime-manifest.json（应改为读 JSON）' % MJS)
        # 检查是否还残留写死的 archive URL
        hard = re.findall(r"archive:\s*`", mjs)
        if hard:
            problems.append('%s 里还有 %d 处写死的 archive' % (MJS, len(hard)))
        # 检查是否还残留写死的 size
        if re.search(r'^\s*size:\s*\d+\s*\*\s*1024', mjs, re.M):
            problems.append('%s 里还有写死的 size' % MJS)

    print()
    if problems:
        print('发现 %d 个问题：' % len(problems))
        for p in problems:
            print('  - %s' % p)
        sys.exit(1)

    print('运行时清单一致性检查通过（%d 个组件，三处同源）' % len(comps))


if __name__ == '__main__':
    main()
