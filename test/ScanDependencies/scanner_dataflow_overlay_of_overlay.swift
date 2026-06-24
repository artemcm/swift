// Continuation-scheduler regression test (NewScannerDesign §8.2.2):
// overlays of overlays. The main module's bridging header makes Clang module F
// visible; F re-exports Clang module G. Both have Swift overlays. Resolving the
// overlay of F expands it through the dataflow, which (a) resolves its own
// transitive Swift import 'Helper' (reachable only via the overlay's
// expansion), and (b) discovers F's overlay-of-overlay G. This replaces the
// phase scanner's synthetic '_<Main>-OverlayDependencies' recursion, so no such
// synthetic module may appear in the output.

// REQUIRES: objc_interop

// RUN: %empty-directory(%t)
// RUN: %empty-directory(%t/inputs)
// RUN: split-file %s %t

// RUN: %target-swift-frontend -scan-dependencies -module-name Test \
// RUN:   -module-cache-path %t/cache \
// RUN:   -disable-implicit-string-processing-module-import \
// RUN:   -disable-implicit-concurrency-module-import -parse-stdlib \
// RUN:   %t/main.swift -o %t/deps.json -I %t/inputs \
// RUN:   -import-objc-header %t/main-header.h

// RUN: %validate-json %t/deps.json | %FileCheck %s
// RUN: %validate-json %t/deps.json | %FileCheck %s --check-prefix=NEGATIVE

// The overlay of F was expanded by the dataflow: its private Swift import
// 'Helper' (not visible to the main module) resolved, and F's own overlay G
// was discovered.
// CHECK-DAG: "swift": "Helper"
// CHECK-DAG: "swift": "G"

// The synthetic overlay-dependencies module must not exist.
// NEGATIVE-NOT: _Test-OverlayDependencies

//--- main.swift
public func test() {}

//--- main-header.h
#include "F.h"

//--- inputs/F.h
#include "G.h"
void f(void);

//--- inputs/G.h
void g(void);

//--- inputs/module.modulemap
module F {
  header "F.h"
  export *
}
module G {
  header "G.h"
  export *
}

//--- inputs/F.swiftinterface
// swift-interface-format-version: 1.0
// swift-module-flags: -module-name F -disable-implicit-string-processing-module-import -disable-implicit-concurrency-module-import -parse-stdlib
@_exported import F
import Helper
public func f_overlay() {}

//--- inputs/G.swiftinterface
// swift-interface-format-version: 1.0
// swift-module-flags: -module-name G -disable-implicit-string-processing-module-import -disable-implicit-concurrency-module-import -parse-stdlib
@_exported import G
public func g_overlay() {}

//--- inputs/Helper.swiftinterface
// swift-interface-format-version: 1.0
// swift-module-flags: -module-name Helper -disable-implicit-string-processing-module-import -disable-implicit-concurrency-module-import -parse-stdlib
public func helper() {}
