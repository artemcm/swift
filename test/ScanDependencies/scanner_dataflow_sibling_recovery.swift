// Continuation-scheduler regression test (NewScannerDesign §8.2.1):
// sibling-recovery via the cache. 'FooAux' is an auxiliary framework module
// declared only inside the 'Foo' framework's modulemap, so a direct by-name
// scan of 'FooAux' cannot find it (there is no FooAux.framework). Scanning
// 'Foo' (whose umbrella header imports 'FooAux' via the framework-qualified
// path) records 'FooAux' transitively; the dataflow's incremental retry then
// resolves the main module's direct 'import FooAux' from the cache. If the
// retry regressed, 'FooAux' would be diagnosed as a missing module and the
// scan would fail.

// REQUIRES: objc_interop

// RUN: %empty-directory(%t)
// RUN: split-file %s %t

// RUN: %target-swift-frontend -scan-dependencies -module-name Test \
// RUN:   -module-cache-path %t/clang-module-cache \
// RUN:   -disable-implicit-string-processing-module-import \
// RUN:   -disable-implicit-concurrency-module-import -parse-stdlib \
// RUN:   %t/main.swift -o %t/deps.json -F %t

// RUN: %FileCheck %s --input-file=%t/deps.json

// The main module resolves both the framework and its modulemap-only auxiliary
// module as direct Clang dependencies (the latter only via the retry).
// CHECK-DAG: "clang": "Foo"
// CHECK-DAG: "clang": "FooAux"

//--- main.swift
import Foo
import FooAux
public func test() {}

//--- Foo.framework/Headers/Foo.h
#include "Foo/FooAux.h"
void foo(void);

//--- Foo.framework/Headers/FooAux.h
void fooAux(void);

//--- Foo.framework/Modules/module.modulemap
framework module Foo {
  header "Foo.h"
  export *
}

framework module FooAux {
  header "FooAux.h"
  export *
}
