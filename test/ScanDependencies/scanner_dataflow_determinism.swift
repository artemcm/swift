// Continuation-scheduler regression test (NewScannerDesign §8.2.5):
// output determinism. The dataflow scans modules in nondeterministic completion
// order, but the recorded dependency lists are re-derived in import order, so
// the emitted dependency graph must be byte-for-byte identical across runs of
// the same inputs. This graph has several modules that resolve in parallel
// (two Swift modules sharing a Clang dependency, plus a direct Clang import).

// RUN: %empty-directory(%t)
// RUN: split-file %s %t

// RUN: %target-swift-frontend -scan-dependencies -module-name Test \
// RUN:   -module-cache-path %t/cache \
// RUN:   -disable-implicit-string-processing-module-import \
// RUN:   -disable-implicit-concurrency-module-import -parse-stdlib \
// RUN:   %t/main.swift -o %t/deps1.json -I %t/inputs

// RUN: %empty-directory(%t/cache)
// RUN: %target-swift-frontend -scan-dependencies -module-name Test \
// RUN:   -module-cache-path %t/cache \
// RUN:   -disable-implicit-string-processing-module-import \
// RUN:   -disable-implicit-concurrency-module-import -parse-stdlib \
// RUN:   %t/main.swift -o %t/deps2.json -I %t/inputs

// The two fresh scans of the same inputs must produce identical dependency
// graphs (the same module cache path is used so content-hashed output paths
// match; the cache is cleared between runs so both scans run from scratch).
// RUN: diff %t/deps1.json %t/deps2.json

//--- main.swift
import Alpha
import Beta
public func test() {}

//--- inputs/Alpha.swiftinterface
// swift-interface-format-version: 1.0
// swift-module-flags: -module-name Alpha -disable-implicit-string-processing-module-import -disable-implicit-concurrency-module-import -parse-stdlib
import Shared
public func alpha() {}

//--- inputs/Beta.swiftinterface
// swift-interface-format-version: 1.0
// swift-module-flags: -module-name Beta -disable-implicit-string-processing-module-import -disable-implicit-concurrency-module-import -parse-stdlib
import Shared
public func beta() {}

//--- inputs/Shared.h
void shared(void);

//--- inputs/Direct.h
void direct(void);

//--- inputs/module.modulemap
module Shared {
  header "Shared.h"
  export *
}
module Direct {
  header "Direct.h"
  export *
}
