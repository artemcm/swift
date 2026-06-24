// Continuation-scheduler regression test (NewScannerDesign §8.2.4):
// overlay of a header-visible Clang module. The main module's bridging header
// imports Clang module 'H' (which is otherwise neither a direct Swift nor a
// direct Clang import), and 'H' has a Swift overlay. Discovering the overlay
// requires the overlay query to run after the header scan, so that H is among
// the module's visible Clang modules. If the overlay query fired before the
// header scan, the overlay of a header-visible Clang module would be missed.

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

// The Swift overlay H of the header-visible Clang module H is discovered as a
// Swift-overlay dependency of the main module.
// CHECK: "swiftOverlayDependencies": [
// CHECK-NEXT: {
// CHECK-NEXT: "swift": "H"
// CHECK-NEXT: }
// CHECK-NEXT: ]

//--- main.swift
public func test() {}

//--- main-header.h
#include "H.h"

//--- inputs/H.h
void h(void);

//--- inputs/module.modulemap
module H {
  header "H.h"
  export *
}

//--- inputs/H.swiftinterface
// swift-interface-format-version: 1.0
// swift-module-flags: -module-name H -disable-implicit-string-processing-module-import -disable-implicit-concurrency-module-import -parse-stdlib
@_exported import H
public func h_overlay() {}
