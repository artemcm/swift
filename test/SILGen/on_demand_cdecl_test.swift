// Test that the on-demand SILGen path matches the legacy path for
// @_cdecl (Underscored) functions, which produce both a Swift entry
// point and a native-to-foreign thunk.
//
// emitAbstractFuncDecl emits the foreign thunk eagerly via
// emitNativeToForeignThunk -> emitFunctionDefinition. The on-demand
// coordinator currently does not call emitAbstractFuncDecl, so the
// thunk is missing from the on-demand output. Phase 5's bootstrap
// sweep should pick the thunk up and route it through the request
// system.

// RUN: %target-swift-emit-sil -parse-as-library %s > %t.normal.sil
// RUN: %target-swift-emit-sil -parse-as-library -Xllvm -sil-on-demand-emission %s > %t.ondemand.sil
// RUN: diff %t.normal.sil %t.ondemand.sil

// RUN: %target-swift-emit-sil -parse-as-library %s | %FileCheck %s

// The foreign-thunk entry, emitted by AuxiliaryDeclEmissionRequest's
// CDeclThunkRequest sub-request.
// CHECK-LABEL: sil hidden [thunk] [asmname "grapefruit"] @$s20on_demand_cdecl_test6orangeyS2iFTo

// The Swift entry point for the @_cdecl function.
// CHECK-LABEL: sil hidden @$s20on_demand_cdecl_test6orangeyS2iF :
@_cdecl("grapefruit")
func orange(_ x: Int) -> Int {
  return x
}

// A peer that calls the Swift entry; the thunk is not referenced from
// any Swift body, so AuxiliaryDeclEmissionRequest is the only mechanism
// that emits it.
// CHECK-LABEL: sil hidden @$s20on_demand_cdecl_test12useFromSwiftyS2iF
func useFromSwift(_ x: Int) -> Int {
  return orange(x)
}
