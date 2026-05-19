// RUN: %target-swift-emit-sil -parse-as-library %s > %t.normal.sil
// RUN: %target-swift-emit-sil -parse-as-library -Xllvm -sil-on-demand-emission %s > %t.ondemand.sil
// RUN: diff %t.normal.sil %t.ondemand.sil

// Verify request evaluator cache counts for the on-demand path.
// RUN: %target-swift-emit-sil -parse-as-library -Xllvm -sil-on-demand-emission -analyze-request-evaluator %s -o /dev/null 2>&1 | %FileCheck --check-prefix=REQUESTS %s

// The on-demand path emits foo, helper, and caller via
// CanonicalSILFunctionRequest, which chains through Diagnosed -> Cleaned
// -> Body -> Interface. Each function produces one evaluation of each
// request type: 3 functions x 5 request types = 15 evaluations.
//
// helper is private and discovered transitively: caller's body scan
// finds a function_ref to helper. The worklist fires
// CanonicalSILFunctionRequest for it.
//
// Phase 5 also fires AuxiliaryDeclEmissionRequest (and its sub-requests)
// for each top-level FuncDecl. These sub-requests early-exit when the
// function has no relevant attribute, but the cache records the
// evaluation.
//
// REQUESTS-DAG: CanonicalSILFunctionRequest{{.*}} 3
// REQUESTS-DAG: DiagnosedSILFunctionRequest{{.*}} 3
// REQUESTS-DAG: CleanedSILFunctionRequest{{.*}} 3
// REQUESTS-DAG: SILFunctionBodyRequest{{.*}} 3
// REQUESTS-DAG: SILFunctionInterfaceRequest{{.*}} 3
// REQUESTS-DAG: AuxiliaryDeclEmissionRequest{{.*}} 3
// REQUESTS-DAG: ArgumentGeneratorsRequest{{.*}} 3
// REQUESTS-DAG: CDeclThunkRequest{{.*}} 3
// REQUESTS-DAG: DistributedThunkRequest{{.*}} 3
// REQUESTS-DAG: BackDeploymentRequest{{.*}} 3

// Both paths must produce identical canonical SIL.

// CHECK-LABEL: sil hidden @$s23on_demand_emission_test3fooyS2iF
// CHECK: bb0(%0 : $Int):
// CHECK:   return
func foo(_ x: Int) -> Int {
  return x
}

// Private function: pulled in transitively when caller is emitted.
// CHECK-LABEL: sil private @$s23on_demand_emission_test6helper33
private func helper(_ x: Int) -> Int {
  return x
}

// CHECK-LABEL: sil hidden @$s23on_demand_emission_test6calleryS2iF
func caller(_ x: Int) -> Int {
  return helper(x)
}
