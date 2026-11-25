// Single-root lowering under lazy type checking. Seeding one root makes the
// coordinator ask for that body alone, so lazy type checking checks only the
// root: another function's type error neither blocks the root's SIL
// diagnostics nor appears beside them.

// RUN: %empty-directory(%t)
// RUN: split-file %s %t

// The root's SIL diagnostics, with the exclusivity fix-it, and nothing from
// broken().
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name Ledger \
// RUN:   -enable-library-evolution -experimental-lazy-typecheck \
// RUN:   -Xllvm -sil-on-demand-emission -Xllvm -sil-on-demand-root=reconcile \
// RUN:   -verify -verify-additional-prefix reconcile- %t/Ledger.swift \
// RUN:   -o /dev/null

// The same root, by the position of its swap.
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name Ledger \
// RUN:   -enable-library-evolution -experimental-lazy-typecheck \
// RUN:   -Xllvm -sil-on-demand-emission -Xllvm -sil-on-demand-root=7:8 \
// RUN:   -verify -verify-additional-prefix reconcile- %t/Ledger.swift \
// RUN:   -o /dev/null

// Only the root's body is type-checked.
// RUN: not %target-swift-frontend -emit-sil -parse-as-library \
// RUN:   -module-name Ledger -enable-library-evolution \
// RUN:   -experimental-lazy-typecheck -Xllvm -sil-on-demand-emission \
// RUN:   -Xllvm -sil-on-demand-root=reconcile -debug-time-function-bodies \
// RUN:   %t/Ledger.swift -o /dev/null 2>&1 | %FileCheck --check-prefix=BODIES %s
// BODIES-NOT: broken()
// BODIES: reconcile(_:from:to:)
// BODIES-NOT: broken()

// Legacy, with the same lazy type checking: SILGen emits every function, so
// broken() is type-checked, and its error stops SIL generation for all.
// RUN: not %target-swift-frontend -emit-sil -parse-as-library \
// RUN:   -module-name Ledger -enable-library-evolution \
// RUN:   -experimental-lazy-typecheck %t/Ledger.swift -o /dev/null 2>&1 \
// RUN:   | %FileCheck --check-prefix=LEGACY %s
// LEGACY: cannot convert return expression of type 'String' to return type 'Int'
// LEGACY-NOT: overlapping accesses
// LEGACY-NOT: used before being initialized

// A root that doesn't type-check: its error, no SIL, and no crash.
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name Ledger \
// RUN:   -enable-library-evolution -experimental-lazy-typecheck \
// RUN:   -Xllvm -sil-on-demand-emission -Xllvm -sil-on-demand-root=broken \
// RUN:   -verify -verify-additional-prefix broken- %t/Ledger.swift \
// RUN:   -o /dev/null

// A root caught mid-edit, which doesn't parse: parse errors, and no crash.
// RUN: not %target-swift-frontend -emit-sil -parse-as-library \
// RUN:   -module-name Ledger -enable-library-evolution \
// RUN:   -experimental-lazy-typecheck -Xllvm -sil-on-demand-emission \
// RUN:   -Xllvm -sil-on-demand-root=reconcile %t/Partial.swift -o /dev/null \
// RUN:   2>&1 | %FileCheck --check-prefix=PARTIAL %s
// PARTIAL: error: expected ']' in expression list

//--- Ledger.swift
func broken() -> Int {
  return "not an int" // expected-broken-error {{cannot convert return expression of type 'String' to return type 'Int'}}
}

func reconcile(_ ledger: inout [Int], from i: Int, to j: Int) -> Int {
  let total: Int // expected-reconcile-note {{constant defined here}}
  swap(&ledger[i], &ledger[j]) // expected-reconcile-error {{overlapping accesses to 'ledger', but modification requires exclusive access; consider calling MutableCollection.swapAt(_:_:)}} {{3-31=ledger.swapAt(i, j)}} expected-reconcile-note {{conflicting access is here}}
  if ledger[i] > 0 { total = ledger[i] }
  return total // expected-reconcile-error {{constant 'total' used before being initialized}}
}

//--- Partial.swift
func reconcile(_ ledger: inout [Int], from i: Int, to j: Int) -> Int {
  let total: Int
  swap(&ledger[i], &ledger[
  if ledger[i] > 0 { total = ledger[i] } else { total = 0 }
  return total
}
