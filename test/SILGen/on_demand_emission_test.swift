// RUN: %target-swift-emit-silgen -parse-as-library %s > %t.normal.sil
// RUN: %target-swift-emit-silgen -parse-as-library -Xllvm -sil-on-demand-emission %s > %t.ondemand.sil
// RUN: %FileCheck %s < %t.normal.sil
// RUN: %FileCheck %s < %t.ondemand.sil

// Verify request evaluator cache counts for the on-demand path.
// RUN: %target-swift-emit-silgen -parse-as-library -Xllvm -sil-on-demand-emission -analyze-request-evaluator %s -o /dev/null 2>&1 | %FileCheck --check-prefix=REQUESTS %s

// The on-demand path emits foo, helper, and caller via SILFunctionBodyRequest.
// Each body request first evaluates SILFunctionInterfaceRequest for the same
// SILDeclRef to get or create the declaration. Thus 3 body + 3 interface.
//
// foo and caller are top-level functions visited directly by
// emitOnDemandViaRequests. helper is private and discovered transitively:
// caller's body emission references helper via SILGenModule::getFunction,
// which queues it in pendingForcedFunctions; the drain loop then fires
// SILFunctionBodyRequest for it.
//
// REQUESTS-DAG: SILFunctionBodyRequest{{[[:space:]]}}3
// REQUESTS-DAG: SILFunctionInterfaceRequest{{[[:space:]]}}3

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
