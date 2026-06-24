// Continuation-scheduler regression test (NewScannerDesign §8.2.3):
// a bridging-header scan racing a direct Clang import. The binary Swift module
// 'Bin' was built with a header that imports Clang module 'Shared'; the main
// module imports both 'Bin' and 'Shared' directly. In the dataflow, Bin's
// header scan and the main module's direct Clang scan touch 'Shared'
// concurrently, and must both resolve it to the same Clang module.

// REQUIRES: objc_interop

// RUN: %empty-directory(%t)
// RUN: %empty-directory(%t/inputs)
// RUN: split-file %s %t

// Build the binary Swift module Bin with a header that imports Clang 'Shared'.
// RUN: %target-swift-frontend -emit-module -o %t/inputs/Bin.swiftmodule \
// RUN:   -module-name Bin -import-objc-header %t/Bin-header.h -I %t/inputs \
// RUN:   -parse-stdlib -disable-implicit-string-processing-module-import \
// RUN:   -disable-implicit-concurrency-module-import %t/bin.swift

// Scan the main module, which imports Bin (header dep on Shared) and Shared.
// RUN: %target-swift-frontend -scan-dependencies -module-name Test \
// RUN:   -module-cache-path %t/cache \
// RUN:   -disable-implicit-string-processing-module-import \
// RUN:   -disable-implicit-concurrency-module-import -parse-stdlib \
// RUN:   %t/main.swift -o %t/deps.json -I %t/inputs

// RUN: %validate-json %t/deps.json | %FileCheck %s

// 'Shared' resolves as both the main module's direct Clang dependency and Bin's
// header Clang dependency.
// CHECK-DAG: "clang": "Shared"
// CHECK: "headerModuleDependencies": [
// CHECK-NEXT: "Shared"

//--- main.swift
import Bin
import Shared
public func test() {}

//--- bin.swift
public func bin() {}

//--- Bin-header.h
#include "Shared.h"

//--- inputs/Shared.h
void shared(void);

//--- inputs/module.modulemap
module Shared {
  header "Shared.h"
  export *
}
