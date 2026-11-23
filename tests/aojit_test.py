#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# AOJIT 脚本编译规则测试。
# 对应 Native/ObjC/SPAOJIT.m 的 directStagesForScript:environment:
import sys

BS = chr(92)
DQ = chr(34)
SQ = chr(39)
NL = chr(10)
CR = chr(13)
TAB = chr(9)

# 与 SPAOJIT.m 的 SPNonPipeMetaSet 一致（管道符单独处理）
NON_PIPE_META = set("&;<>$`()*?[]{}~!" + BS + SQ + DQ + NL + CR + TAB)
NEWLINE = set(NL + CR)
WS = set(" " + TAB)


def has_non_pipe_meta(s):
    return any(c in NON_PIPE_META for c in s)


def has_newline(s):
    return any(c in NEWLINE for c in s)


def split_words(s):
    out, cur = [], []
    for c in s:
        if c in WS:
            if cur:
                out.append("".join(cur))
                cur = []
        else:
            cur.append(c)
    if cur:
        out.append("".join(cur))
    return out


def stage_argv(stage, resolve):
    t = stage.strip(" " + TAB)
    if not t:
        return None
    if has_non_pipe_meta(t):
        return None
    words = split_words(t)
    if not words:
        return None
    exe = resolve(words[0])
    if not exe:
        return None
    return [exe] + words[1:]


def compile_script(script, resolve):
    if not script:
        return None
    t = script.strip(" " + TAB + NL + CR)
    if not t:
        return None
    if has_newline(t):
        return None

    if "|" not in t:
        one = stage_argv(t, resolve)
        return [one] if one else None

    if "||" in t or "|&" in t:
        return None

    stages = []
    for part in t.split("|"):
        argv = stage_argv(part, resolve)
        if not argv:
            return None
        stages.append(argv)
    return stages if len(stages) >= 2 else None


FAKE = {
    "ls": "/bin/ls", "cat": "/bin/cat", "grep": "/usr/bin/grep",
    "head": "/usr/bin/head", "wc": "/usr/bin/wc",
}


def resolve(name):
    if name.startswith("/"):
        return name if name in FAKE.values() else None
    return FAKE.get(name)


CASES = [
    ("ls", 1, "单命令"),
    ("ls -l /tmp", 1, "单命令带参数"),
    ("ls | wc -l", 2, "两段管道"),
    ("cat foo | grep bar | wc -l", 3, "三段管道"),
    ("/bin/ls -a", 1, "绝对路径命令"),
    ("ls && rm -rf /", None, "&& 是 shell 语法"),
    ("ls || true", None, "|| 是逻辑或"),
    ("echo $HOME", None, "$ 变量展开"),
    ("ls *.m", None, "通配符"),
    ("cat < in > out", None, "重定向"),
    ("ls; pwd", None, "分号"),
    ("ls `pwd`", None, "命令替换"),
    ("cd /tmp && ls", None, "多命令"),
    ("make -j4" + NL + "ls", None, "多行脚本"),
    ("nosuchcmd -x", None, "命令不存在"),
    ("ls | nosuchcmd", None, "管道中一段失败"),
    ("ls |& wc", None, "|& 不是简单管道"),
    ("", None, "空脚本"),
]


def main():
    failed = 0
    for script, expect, desc in CASES:
        got = compile_script(script, resolve)
        n = len(got) if got else None
        ok = (n == expect)
        if not ok:
            failed += 1
        mark = "OK" if ok else "FAIL"
        print("[%s] %-28s expect=%s got=%s  %r" % (mark, desc, expect, n, script))
        if ok and got:
            for i, argv in enumerate(got, 1):
                print("      [%d] %s" % (i, argv))

    print()
    if failed:
        print("失败 %d / %d" % (failed, len(CASES)))
        sys.exit(1)
    print("全部通过（%d 项）" % len(CASES))
    print("要点：含任何 shell 元字符的脚本一律回落 sh，保证语义与原来完全一致。")


if __name__ == "__main__":
    main()
