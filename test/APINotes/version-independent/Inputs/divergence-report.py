#!/usr/bin/env python3
# divergence-report.py - Report where version-independent API notes diverge
#
# This source file is part of the Swift.org open source project
#
# Copyright (c) 2026 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See https://swift.org/LICENSE.txt for license information
# See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
#
# ----------------------------------------------------------------------------
#
# Usage: divergence-report.py <output directory> <version>...
#
# Reads the prints the harness in ../lit.local.cfg leaves in the output
# directory, and writes to stdout every error a print reported and every
# captured print that differs from the default-mode print at its version. A
# difference identical to the one before it at the same version is reported by
# reference, so a divergence that depends on the building version stands out.
# The output is empty when the two modes agree everywhere.
#
# ----------------------------------------------------------------------------

import difflib
import os
import re
import sys


def read_lines(path):
    with open(path) as f:
        return f.read().splitlines()


def report_errors(directory, output):
    # Directories name the module cache and the test's output directory, which
    # differ between machines and runs.
    errors = [re.sub(r"/[^ ']*/", '', line)
              for line in read_lines(os.path.join(directory, output + '.err'))
              if 'error:' in line]
    if errors:
        print('=== ' + output + ': errors')
        for line in errors:
            print(line)


def main():
    directory, versions = sys.argv[1], sys.argv[2:]

    for read in versions:
        report_errors(directory, 'default-' + read)

    for read in versions:
        oracle = 'default-' + read
        expected = read_lines(os.path.join(directory, oracle + '.txt'))
        previous = None
        for built in versions:
            output = 'capture-' + built + '-at-' + read
            report_errors(directory, output)
            actual = read_lines(os.path.join(directory, output + '.txt'))
            if actual == expected:
                continue
            if previous and actual == previous[1]:
                print('=== ' + output + ': same as ' + previous[0])
                continue
            previous = (output, actual)
            print('=== ' + output + ': differs from ' + oracle)
            for line in difflib.unified_diff(expected, actual, oracle, output,
                                             n=0, lineterm=''):
                print(line)


if __name__ == '__main__':
    main()
