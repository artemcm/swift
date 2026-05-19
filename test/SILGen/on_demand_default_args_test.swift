// Test that the on-demand SILGen path matches the legacy path for
// functions with default-argument generators.
//
// Default-arg generators are emitted by emitAbstractFuncDecl via
// emitArgumentGenerators -> emitDefaultArgGenerator -> emitOrDelayFunction.
// The on-demand coordinator currently does not call emitAbstractFuncDecl,
// so the generators are only created when caller bodies trigger
// SILGenModule::getFunction. Phase 5 routes them through the request
// system explicitly.

// RUN: %target-swift-emit-sil -parse-as-library %s > %t.normal.sil
// RUN: %target-swift-emit-sil -parse-as-library -Xllvm -sil-on-demand-emission %s > %t.ondemand.sil
// RUN: diff %t.normal.sil %t.ondemand.sil

// RUN: %target-swift-emit-sil -parse-as-library %s | %FileCheck %s

// Verify request evaluator cache counts. Three top-level functions
// plus two default-arg generators = 5 SILDeclRefs through the
// per-function chain. SILFunctionInterfaceRequest also caches stdlib
// callee interfaces discovered during body emission, so its count is
// higher than 5. The three top-level FuncDecls each fire
// AuxiliaryDeclEmissionRequest and the per-feature sub-requests.
// RUN: %target-swift-emit-sil -parse-as-library -Xllvm -sil-on-demand-emission \
// RUN:   -analyze-request-evaluator %s -o /dev/null 2>&1 | %FileCheck --check-prefix=REQUESTS %s

// REQUESTS-DAG: CanonicalSILFunctionRequest{{.*}} 5
// REQUESTS-DAG: DiagnosedSILFunctionRequest{{.*}} 5
// REQUESTS-DAG: CleanedSILFunctionRequest{{.*}} 5
// REQUESTS-DAG: SILFunctionBodyRequest{{.*}} 5
// REQUESTS-DAG: SILFunctionInterfaceRequest{{.*}} 7
// REQUESTS-DAG: AuxiliaryDeclEmissionRequest{{.*}} 3
// REQUESTS-DAG: ArgumentGeneratorsRequest{{.*}} 3
// REQUESTS-DAG: CDeclThunkRequest{{.*}} 3
// REQUESTS-DAG: DistributedThunkRequest{{.*}} 3
// REQUESTS-DAG: BackDeploymentRequest{{.*}} 3

// helper: two default arguments. The default-arg generators are
// emitted before the helper body in the SIL output.
// CHECK-LABEL: sil hidden @$s27on_demand_default_args_test6helperyS2i_SitFfA_ :
// CHECK-LABEL: sil hidden @$s27on_demand_default_args_test6helperyS2i_SitFfA0_ :
// CHECK-LABEL: sil hidden @$s27on_demand_default_args_test6helperyS2i_SitF :
func helper(_ x: Int = 17, _ y: Int = 42) -> Int {
  return x + y
}

// callerNoArgs: triggers both default generators.
// CHECK-LABEL: sil hidden @$s27on_demand_default_args_test12callerNoArgsSiyF
func callerNoArgs() -> Int {
  return helper()
}

// callerOneArg: triggers only the second default generator.
// CHECK-LABEL: sil hidden @$s27on_demand_default_args_test12callerOneArgyS2iF
func callerOneArg(_ x: Int) -> Int {
  return helper(x)
}
