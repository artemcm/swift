#!/usr/bin/env python3
# verify_gap_check.py ---------------------------------------------*- python -*-
#
# This source file is part of the Swift.org open source project
#
# Copyright (c) 2014 - 2026 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See https://swift.org/LICENSE.txt for license information
# See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
# ----------------------------------------------------------------------------
"""Check the expected diagnostics that an on-demand -verify run left
unproduced: each must be in an allowed context, and the run may produce
nothing unexpected.

Usage: verify_gap_check.py SOURCE STDERR --allow CONTEXT [--allow CONTEXT ...]

A missing line's context comes from its owner: the nearest line above it
that starts at column 0 with a declaration keyword, after attributes and
modifiers. The context is protocol-extension for `extension NAME` when
SOURCE declares `protocol NAME`; top-level for a `func`, `var`, or `let`, a
top-level statement, or no owner at all; otherwise the keyword: class,
struct, enum, actor, protocol, or extension (of a type). One message is
top-level wherever it is: definite initialization of top-level code reports
"used by function definition before being initialized" at the declaration
that reads the global, a method of a class, say.

Exits 0 when every missing line's context is allowed and something is still
missing. Exits 1, with the reasons, on an unexpected diagnostic, a missing
line in a context that isn't allowed, a crash, or when nothing is missing:
then the test should run under plain -verify.
"""
import argparse
import re
import sys

MODIFIERS = (r"(?:(?:public|package|internal|private|fileprivate|open|final|"
             r"nonisolated|indirect|distributed|static|override)\s+)*")
ATTRIBUTES = r"(?:@\w+(?:\([^)]*\))?\s+)*"
OWNER = re.compile(r"^" + ATTRIBUTES + MODIFIERS +
                   r"(class|struct|enum|actor|protocol|extension|func|var|let)"
                   r"\b\s*(\w*)")
PROTOCOL = re.compile(r"^\s*" + ATTRIBUTES + MODIFIERS + r"protocol\s+(\w+)")
MISSING = re.compile(r":(\d+):\d+: error: expected "
                     r"(?:error|warning|note|remark) not produced")
UNEXPECTED = re.compile(r"unexpected (?:error|warning|note|remark) produced")
TOP_LEVEL_CODE_MESSAGE = "used by function definition before being initialized"


def context(src, protocols, line):
    if TOP_LEVEL_CODE_MESSAGE in src[line - 1]:
        return "top-level"
    for i in range(line - 1, -1, -1):
        text = src[i]
        if not text or text[0].isspace() or text.startswith(("}", "//", "#")):
            continue
        if text.startswith(("@", "import ")):
            continue
        m = OWNER.match(text)
        if not m:
            return "top-level"  # a top-level statement
        kind, name = m.group(1), m.group(2)
        if kind == "extension":
            return "protocol-extension" if name in protocols else "extension"
        if kind in ("func", "var", "let"):
            return "top-level"
        return kind
    return "top-level"


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("source")
    parser.add_argument("stderr")
    parser.add_argument("--allow", action="append", default=[])
    args = parser.parse_args()

    src = open(args.source).read().splitlines()
    err = open(args.stderr).read()
    if "Stack dump" in err or "Assertion failed" in err:
        print("the compiler crashed")
        return 1
    protocols = {m.group(1) for m in map(PROTOCOL.match, src) if m}
    missing = sorted({int(m.group(1)) for m in MISSING.finditer(err)})
    problems = ["unexpected: " + l.strip()
                for l in err.splitlines() if UNEXPECTED.search(l)]
    contexts = {}
    for line in missing:
        contexts[line] = context(src, protocols, line)
        if contexts[line] not in args.allow:
            problems.append(f"line {line}: a missing diagnostic in "
                            f"{contexts[line]}, which isn't allowed")
    if problems:
        print("\n".join(problems))
        return 1
    if not missing:
        print("no gaps left: run the test under -verify")
        return 1
    print(f"{len(missing)} lines with missing diagnostics, in: "
          + ", ".join(sorted(set(contexts.values()))))
    return 0


if __name__ == "__main__":
    sys.exit(main())
