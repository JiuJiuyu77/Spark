#!/usr/bin/env python3
"""Makefile 变量解析测试。

对应 Native/ObjC/SPModels.m 的 -firstValueOfMakeVar:in:
第 1043 轮重写后，必须能正确处理 Theos 常见的几种写法。

之前只认 `TWEAK_NAME=`（等号紧贴行首），
而 Theos 惯例是 `TWEAK_NAME = xxx`（等号两边有空格），
导致自己新建的工程都解析不出产品名。
"""
import sys

NAME_CHARS = set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_")


def first_value(makefile, var):
    """等价复刻 ObjC 实现。"""
    for raw in makefile.split("\n"):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue

        i = 0
        while i < len(line) and line[i] in NAME_CHARS:
            i += 1
        if i == 0:
            continue

        name = line[:i]
        if name != var:
            continue

        while i < len(line) and line[i] in " \t":
            i += 1

        assign = False
        if i < len(line):
            c = line[i]
            if c == "=":
                assign = True
                i += 1
            elif c in "?:+" and i + 1 < len(line) and line[i + 1] == "=":
                assign = True
                i += 2
        if not assign:
            continue

        v = line[i:].strip()

        # 剥掉引号外的行尾注释
        in_q = False
        q = ""
        out = []
        for ch in v:
            if in_q:
                out.append(ch)
                if ch == q:
                    in_q = False
            elif ch in "\"'":
                in_q = True
                q = ch
                out.append(ch)
            elif ch == "#":
                break
            else:
                out.append(ch)
        v = "".join(out).strip()

        if v.startswith("$"):
            continue
        if len(v) >= 2 and ((v[0] == '"' and v[-1] == '"') or (v[0] == "'" and v[-1] == "'")):
            v = v[1:-1]
        return v or None
    return None


CASES = [
    ("空格等号", "TWEAK_NAME = SparkDemo", "SparkDemo"),
    ("无空格", "TWEAK_NAME=SparkDemo", "SparkDemo"),
    ("问号赋值", "TWEAK_NAME ?= SparkDemo", "SparkDemo"),
    ("冒号赋值", "TWEAK_NAME := SparkDemo", "SparkDemo"),
    ("加号赋值", "TWEAK_NAME += SparkDemo", "SparkDemo"),
    ("制表符", "TWEAK_NAME\t=\tSparkDemo", "SparkDemo"),
    ("行尾注释", "TWEAK_NAME = SparkDemo # 注释", "SparkDemo"),
    ("引号包裹", 'TWEAK_NAME = "Spark Demo"', "Spark Demo"),
    ("引用变量", "TWEAK_NAME = $(NAME)", None),
    ("变量名后缀", "TWEAK_NAME_SUFFIX = X", None),
    ("被注释掉", "# TWEAK_NAME = X", None),
    ("多行取首个", "A = 1\nTWEAK_NAME = First\nTWEAK_NAME = Second", "First"),
    ("前导空格", "   TWEAK_NAME = Indented", "Indented"),
    (
        "真实 Makefile",
        "ARCHS = arm64\nTARGET = iphone:clang:latest:15.0\n\n"
        "TWEAK_NAME = Hush\nHush_FILES = Tweak.x",
        "Hush",
    ),
    # 其余产品名变量
    ("APPLICATION_NAME", "APPLICATION_NAME = MyApp", "MyApp"),
    ("LIBRARY_NAME", "LIBRARY_NAME = Lib", "Lib"),
    ("TOOL_NAME", "TOOL_NAME = cli", "cli"),
    ("BUNDLE_NAME", "BUNDLE_NAME = Prefs", "Prefs"),
]


def main():
    ok = 0
    for label, text, expect in CASES:
        var = "TWEAK_NAME"
        for candidate in ("APPLICATION_NAME", "LIBRARY_NAME", "TOOL_NAME", "BUNDLE_NAME"):
            if text.lstrip().startswith(candidate):
                var = candidate
        got = first_value(text, var)
        passed = got == expect
        ok += passed
        mark = "✓" if passed else "✗"
        print(f"{mark} {label:16s} 期望={expect!r:14s} 实际={got!r}")

    total = len(CASES)
    print(f"\n{ok}/{total} 通过")
    return 0 if ok == total else 1


if __name__ == "__main__":
    sys.exit(main())