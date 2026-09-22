// The acceptance test for rdar://109425766, and it does not pass yet.
//
// The radar asks for one Clang module that serves clients at every Swift
// language mode. So the test is: scan the same import at two -swift-version
// values in version-independent mode, and require the scanner to name one
// Clang module, not two.
//
// It fails today, and the cause is not API notes. Comparing the VersionMatrix
// Clang module's command line at -swift-version 4 against -swift-version 5,
// with a shared module cache:
//
//   legacy mode   2 arguments differ: -fapinotes-swift-version= and
//                 -D__swift__=, plus the derived .pcm output path
//   capture mode  1 argument differs: -D__swift__=, plus the derived path
//
// So version-independent API notes removes the argument it set out to remove,
// and the module still forks, because `-D__swift__=<version>` is on every Clang
// command line Swift builds and a single differing -D changes the Clang context
// hash. Adding any one unrelated -D at a fixed -swift-version produces a second
// context hash in the same way.
//
// `__swift__` is not removable on its own terms. SDK headers branch on it, so
// two Swift language modes really can see different declarations from the same
// header, and the context hash cannot tell a header that branches on it from one
// that does not. Closing this gap needs a separate decision about `__swift__`,
// not more API notes work.
//
// What already works, and is covered elsewhere: one capture-mode .pcm *can*
// serve two language modes once something hands it to both. That is
// version-independent.swift, which pins the module path in an explicit module
// map and resolves a 4.0-slice name and a 5.0-slice name out of the one file.
// The gap is that the scanner, left to choose for itself, still asks for two.
//
// When this starts XPASSing, the feature delivers its stated benefit. Move the
// assertion into a green test at that point and delete this file.

// REQUIRES: objc_interop
// XFAIL: *

// RUN: %empty-directory(%t)

// One module cache for both scans, so a shared module would in fact be shared.
// RUN: %target-swift-frontend -scan-dependencies %s -o %t/capture-4.json \
// RUN:   -I %S/Inputs/version-matrix -swift-version 4 \
// RUN:   -module-cache-path %t/mcp -version-independent-apinotes
// RUN: %validate-json %t/capture-4.json

// RUN: %target-swift-frontend -scan-dependencies %s -o %t/capture-5.json \
// RUN:   -I %S/Inputs/version-matrix -swift-version 5 \
// RUN:   -module-cache-path %t/mcp -version-independent-apinotes
// RUN: %validate-json %t/capture-5.json

// The .pcm filename carries the Clang context hash, so comparing the two names
// compares the two hashes.
// RUN: sed -n 's|.*/\(VersionMatrix-[A-Z0-9]*\.pcm\).*|\1|p' %t/capture-4.json | sort -u > %t/pcm-4.txt
// RUN: sed -n 's|.*/\(VersionMatrix-[A-Z0-9]*\.pcm\).*|\1|p' %t/capture-5.json | sort -u > %t/pcm-5.txt

// Guard against the failure mode where neither scan named the module and the
// comparison passes on two empty files.
// RUN: %FileCheck %s --check-prefix=NONEMPTY --input-file %t/pcm-4.txt
// NONEMPTY: VersionMatrix-{{[A-Z0-9]+}}.pcm

// RUN: %diff %t/pcm-4.txt %t/pcm-5.txt

import VersionMatrix
