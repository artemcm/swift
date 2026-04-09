// RUN: %target-swift-emit-silgen -parse-as-library %s > %t.normal.sil
// RUN: %target-swift-emit-silgen -parse-as-library -Xllvm -sil-on-demand-emission %s > %t.ondemand.sil
// RUN: %FileCheck %s < %t.normal.sil
// RUN: %FileCheck %s < %t.ondemand.sil

// Both paths must produce SIL containing the same functions.
// The on-demand path bypasses emitSourceFile entirely and uses
// emitFunctionOnDemand as the sole emission mechanism.

// CHECK-LABEL: sil hidden [ossa] @$s23on_demand_emission_test3fooyS2iF
// CHECK: bb0(%0 : $Int):
// CHECK:   return
func foo(_ x: Int) -> Int {
  return x
}

// Private function: pulled in transitively when caller is emitted.
// CHECK-LABEL: sil private [ossa] @$s23on_demand_emission_test6helper33
private func helper(_ x: Int) -> Int {
  return x + 1
}

// CHECK-LABEL: sil hidden [ossa] @$s23on_demand_emission_test6calleryS2iF
func caller(_ x: Int) -> Int {
  return helper(x)
}
