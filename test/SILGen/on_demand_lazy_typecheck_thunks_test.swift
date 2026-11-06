// Under -experimental-lazy-typecheck, legacy gates a declaration's own entry
// points on shouldEmitFunctionBody, and declines them all once an error has
// been diagnosed. The functions that SILGen makes from a declaration are not
// gated: emitAbstractFuncDecl emits them whatever the gate says. They are the
// native-to-foreign thunk of a @_cdecl function, and the fallback and the
// thunk of a @backDeployed one (distributed thunks and derivative functions
// likewise). The gate on SILFunctionBodyRequest (D15) must leave them out too:
// declined, they would stay declarations, where legacy defines them.

// REQUIRES: asserts
// REQUIRES: OS=macosx

// RUN: %target-swift-frontend -emit-sil -parse-as-library \
// RUN:   -enable-library-evolution -module-name Test \
// RUN:   -experimental-lazy-typecheck -verify %s -o /dev/null
// RUN: %target-swift-frontend -emit-sil -parse-as-library \
// RUN:   -enable-library-evolution -module-name Test \
// RUN:   -experimental-lazy-typecheck -verify %s -o /dev/null \
// RUN:   -Xllvm -sil-on-demand-emission

// The request trace shows that the body requests ran, and that none of them
// was declined.
// RUN: %target-swift-frontend -emit-sil -parse-as-library \
// RUN:   -enable-library-evolution -module-name Test \
// RUN:   -experimental-lazy-typecheck -verify %s -o /dev/null \
// RUN:   -Xllvm -sil-on-demand-emission -Xllvm -debug-only=silgen-requests \
// RUN:   2>&1 | %FileCheck --implicit-check-not='[declined]' %s

func uses(_ v: Nonexistent) {} // expected-error {{cannot find type 'Nonexistent' in scope}}

@_cdecl("my_c_func") public func myC() {}

@available(macOS 10.15, *)
@backDeployed(before: macOS 99)
public func backDeployedF() -> Int { return 1 }

// CHECK: SILFunctionBodyRequest: #myC!foreign
// CHECK: SILFunctionBodyRequest: #backDeployedF
