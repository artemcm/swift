// Audit probe: does the on-demand path handle closures emitted
// synchronously during body emission?
//
// Closures (SGM.emitClosure) get a SILDeclRef keyed on the
// AbstractClosureExpr and are registered with setDeclRef via
// getFunction. discoverCallees bypasses the primary-file filter for
// closure-keyed SILDeclRefs (calleeRef.hasDecl() is false for them).

// RUN: %target-swift-emit-sil -parse-as-library %s > %t.normal.sil
// RUN: %target-swift-emit-sil -parse-as-library -Xllvm -sil-on-demand-emission %s > %t.ondemand.sil
// RUN: diff %t.normal.sil %t.ondemand.sil

func apply(_ f: () -> Int) -> Int { return f() }

func usesClosure(_ x: Int) -> Int {
  return apply({ x + 1 })
}
