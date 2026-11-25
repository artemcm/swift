// Legacy emits a file's local types after its top-level declarations
// (SILGenModule::emitSourceFile), and on demand now does the same. Without
// this, a local class had no vtable, and -c crashed (D7). Local actors are
// covered by Concurrency/flow_isolation_basic.swift
// (on_demand_flow_isolation_test.swift); their witness tables wait for
// witness table support.

// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M %s \
// RUN:   -o %t.legacy.sil
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M %s \
// RUN:   -o %t.ondemand.sil -sil-verify-all -Xllvm -sil-on-demand-emission
// RUN: diff %t.legacy.sil %t.ondemand.sil
// RUN: %FileCheck %s < %t.ondemand.sil
// RUN: %target-swift-frontend -c -parse-as-library -module-name M %s \
// RUN:   -o %t.o -Xllvm -sil-on-demand-emission

func makeLocal() -> Int {
  class Local {
    var z = 2
    func get() -> Int { return z }
    deinit {}
  }
  struct Pair {
    var a = 1
    func sum() -> Int { return a &+ 1 }
  }
  return Local().get() &+ Pair().sum()
}

// CHECK: sil_vtable Local {
