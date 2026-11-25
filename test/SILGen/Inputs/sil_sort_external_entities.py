#!/usr/bin/env python3
# sil_sort_external_entities.py ----------------------------------*- python -*-
#
# This source file is part of the Swift.org open source project
#
# Copyright (c) 2014 - 2026 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See https://swift.org/LICENSE.txt for license information
# See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
# ----------------------------------------------------------------------------
"""
Normalize the order of the entities a .sil file holds from other modules.

Usage: sil_sort_external_entities.py <module name> < input.sil > output.sil

Prints the file's header, then the entities of the named module in their
original order, then every other entity sorted by its first line, then the
lines after the last entity. An entity is a function, a function declaration,
a global, or a table, together with the comment lines above it. A function or
global belongs to the module if its mangled name does; a witness table, if it
names the module; every vtable, property, and move-only deinit table counts as
the module's.

Two outputs that differ only in the order in which the SIL linker deserialized
other modules' functions normalize to the same text, and every entity's text
is still compared. Legacy SIL generation links the whole module after
inlining all of it; on-demand generation links each function as it is
canonicalized, so the order of the deserialized functions differs.
"""

import re
import sys

ENTITY = re.compile(
    r'^(sil_global|sil_vtable|sil_witness_table|sil_default_witness_table|'
    r'sil_property|sil_moveonlydeinit|sil_differentiability_witness|sil)\b')
SYMBOL = re.compile(r'@(\S+?)(?=[\s:]|$)')


def split(lines):
    header, entities, pending = [], [], []
    seen_entity = False
    i = 0
    while i < len(lines):
        line = lines[i]
        match = ENTITY.match(line)
        if not match:
            pending.append(line)
            i += 1
            continue
        if not seen_entity:
            # The header ends above the comment lines of the first entity.
            j = len(pending)
            while j > 0 and pending[j - 1].startswith('//'):
                j -= 1
            header, pending = pending[:j], pending[j:]
            seen_entity = True
        kind = match.group(1)
        body = [line]
        i += 1
        if line.rstrip().endswith('{'):
            while i < len(lines):
                body.append(lines[i])
                i += 1
                last = body[-1]
                if kind == 'sil':
                    if last.startswith('} // end sil function'):
                        break
                elif last.rstrip() == '}':
                    break
        entities.append((kind, body[0], pending + body))
        pending = []
    return header, entities, pending


def is_own(kind, first, module):
    if kind in ('sil', 'sil_global'):
        symbol = SYMBOL.search(first)
        prefix = '$s%d%s' % (len(module), module)
        return bool(symbol) and symbol.group(1).startswith(prefix)
    if kind in ('sil_witness_table', 'sil_default_witness_table'):
        return re.search(r'\bmodule %s\b' % re.escape(module), first) is not None
    return True


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    module = sys.argv[1]
    header, entities, trailer = split(sys.stdin.readlines())
    own = [text for kind, first, text in entities if is_own(kind, first, module)]
    other = sorted((first, ''.join(text)) for kind, first, text in entities
                   if not is_own(kind, first, module))
    sys.stdout.write(''.join(header))
    for text in own:
        sys.stdout.write(''.join(text))
    for _, text in other:
        sys.stdout.write(text)
    sys.stdout.write(''.join(trailer))


if __name__ == '__main__':
    main()
