// Phase 6.3, single-root lowering: the root's compilation emits the witness
// tables of the conformances that the code it emits uses, among those that
// its files declare, and nothing more: the tables, and those that their
// entries use in turn (a base protocol's, an associated conformance's). Each
// table, and its witness thunks, are the legacy ones; a witness outside the
// root's scope stays a declaration, so lazy type checking still checks no
// other body.

// RUN: %empty-directory(%t)
// RUN: split-file %s %t

// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   %t/Tables.swift -o %t/legacy.sil
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   %t/Tables.swift -o %t/root.sil -sil-verify-all \
// RUN:   -Xllvm -sil-on-demand-emission -Xllvm -sil-on-demand-root=root
// RUN: %FileCheck %s < %t/root.sil

// RUN: sed -n '/^sil_witness_table hidden S: P /,/^}/p' %t/legacy.sil > %t/SP.legacy
// RUN: sed -n '/^sil_witness_table hidden S: P /,/^}/p' %t/root.sil > %t/SP.root
// RUN: diff %t/SP.legacy %t/SP.root
// RUN: sed -n '/^sil_witness_table hidden U: P /,/^}/p' %t/legacy.sil > %t/UP.legacy
// RUN: sed -n '/^sil_witness_table hidden U: P /,/^}/p' %t/root.sil > %t/UP.root
// RUN: diff %t/UP.legacy %t/UP.root
// RUN: sed -n '/^sil_witness_table hidden U: Q /,/^}/p' %t/legacy.sil > %t/UQ.legacy
// RUN: sed -n '/^sil_witness_table hidden U: Q /,/^}/p' %t/root.sil > %t/UQ.root
// RUN: diff %t/UQ.legacy %t/UQ.root
// RUN: sed -n '/^sil private \[transparent\] \[thunk\] @$s1M1UVAA1QA2aDP1g1AQzyFTW /,/^} \/\/ end/p' %t/legacy.sil > %t/thunk.legacy
// RUN: sed -n '/^sil private \[transparent\] \[thunk\] @$s1M1UVAA1QA2aDP1g1AQzyFTW /,/^} \/\/ end/p' %t/root.sil > %t/thunk.root
// RUN: diff %t/thunk.legacy %t/thunk.root
// RUN: %FileCheck --check-prefix=THUNK %s < %t/thunk.root
// THUNK: function_ref @$s1M1UV1gAA1SVyF

// CHECK-DAG: sil_witness_table hidden S: P module M {
// CHECK-DAG: sil_witness_table hidden U: P module M {
// CHECK-DAG: sil_witness_table hidden U: Q module M {
// CHECK-DAG: sil private [transparent] [thunk] @$s1M1UVAA1QA2aDP1g1AQzyFTW :
// The witnesses outside the root's scope are declarations:
// CHECK-DAG: sil hidden_external @$s1M1UV1gAA1SVyF :
// CHECK-NOT: sil_witness_table hidden Unused

// Under lazy type checking, a conformance whose witness doesn't type-check
// neither stops the root nor is emitted.
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   -enable-library-evolution -experimental-lazy-typecheck \
// RUN:   %t/Tables.swift %t/Broken.swift -o %t/lazy.sil \
// RUN:   -Xllvm -sil-on-demand-emission -Xllvm -sil-on-demand-root=root
// RUN: %FileCheck --check-prefix=LAZY %s < %t/lazy.sil
// LAZY-DAG: sil_witness_table {{.*}}S: P module M {
// LAZY-DAG: sil_witness_table {{.*}}U: Q module M {
// LAZY-NOT: sil_witness_table {{.*}}Broken

// And only the root's body is type-checked: declaring a witness, or the
// callee use(_:), doesn't check its body (isEmittedOnDemand asks
// shouldEmitFunctionBody last).
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   -enable-library-evolution -experimental-lazy-typecheck \
// RUN:   %t/Tables.swift %t/Broken.swift -o /dev/null \
// RUN:   -Xllvm -sil-on-demand-emission -Xllvm -sil-on-demand-root=root \
// RUN:   -debug-time-function-bodies 2>&1 | %FileCheck --check-prefix=BODIES %s
// BODIES-NOT: {{^[0-9.]+ms.*(\.f\(\)|\.g\(\)|use@)}}
// BODIES: root()
// BODIES-NOT: {{^[0-9.]+ms.*(\.f\(\)|\.g\(\)|use@)}}

//--- Tables.swift
protocol P { func f() -> Int }
protocol Q: P { associatedtype A: P; func g() -> A }
struct S: P { func f() -> Int { 1 } }
struct U: Q { func f() -> Int { 2 }; func g() -> S { S() } }
struct Unused: P { func f() -> Int { 3 } }
func use(_ p: some P) -> Int { p.f() }
func root() -> Int {
  let q: any Q = U()
  return q.f() + use(S())
}

//--- Broken.swift
struct Broken: P { func f() -> Int { "x" } }
func useBroken() -> Int { use(Broken()) }
