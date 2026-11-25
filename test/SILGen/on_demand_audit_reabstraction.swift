// Audit probe: reabstraction thunks in the on-demand path.
//
// Reabstraction thunks are created by getOrCreateReabstractionThunk
// (SILGenThunk.cpp:608) via builder.getOrCreateSharedFunction (string-
// name factory). They have NO setDeclRef call -> getDeclRef() empty.
// discoverCallees skips them via the !calleeRef guard.
//
// However, they are tagged IsTransparent. OnDemandMandatoryInlining
// may inline them away before the standalone canonical form matters.
// This test probes that interaction.
//
// A closure literal at a generic call site is emitted directly in
// the substituted abstraction pattern, so no thunk is generated. To
// force getOrCreateReabstractionThunk we pass a named function
// value: adder has type @convention(thin) (Int) -> Int and must be
// reabstracted to consume's substituted parameter type
// @callee_guaranteed (@in_guaranteed Int) -> @out Int.

// RUN: %target-swift-emit-sil -parse-as-library %s > %t.normal.sil
// RUN: %target-swift-emit-sil -parse-as-library -Xllvm -sil-on-demand-emission %s > %t.ondemand.sil
// RUN: diff %t.normal.sil %t.ondemand.sil

// Confirm the audit is non-vacuous: a reabstraction thunk must be
// present in the canonical SIL.
// RUN: %target-swift-emit-sil -parse-as-library %s | %FileCheck %s
// CHECK: sil {{.*}} [reabstraction_thunk] {{.*}}TR

func adder(_ x: Int) -> Int { return x + 1 }
func consume<T>(_ v: T, _ f: (T) -> T) -> T { return f(v) }

func usesReabstraction(_ x: Int) -> Int {
  return consume(x, adder)
}
