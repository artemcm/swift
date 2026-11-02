// RUN: %target-swift-frontend -emit-sil %s -o /dev/null -verify -D CONFLICT -Xllvm -sil-on-demand-emission -Xllvm -sil-on-demand-closure-groups
// RUN: %target-swift-frontend -emit-sil %s -module-name T -o /dev/null -Xllvm -sil-on-demand-emission -Xllvm -sil-on-demand-closure-groups -Xllvm -debug-only=silgen-requests 2>&1 | %FileCheck %s --check-prefix=COMPONENT
// RUN: %target-swift-frontend -emit-sil %s -module-name T -Xllvm -sil-on-demand-emission -Xllvm -sil-on-demand-closure-groups -o - 2>/dev/null | %FileCheck %s

// REQUIRES: asserts

// On demand, -sil-on-demand-closure-groups runs the closure group passes
// (MarkNeverWritten, CapturePromotion, AccessEnforcementSelection, and
// DiagnoseStaticExclusivity) once per closure component: the root, and the
// closures and local functions it references, transitively. Without it, the
// function-only pipeline omits them, and a function with an access marker
// aborts the verifier (D2).

// A local var captured by a closure: AccessEnforcementSelection selects its
// enforcement, for the parent and the closure together.
// COMPONENT: [component] $s1T8localVaryS2iF: $s1T8localVaryS2iF $s1T8localVaryS2iFyycfU_
// CHECK-LABEL: sil hidden @$s1T8localVaryS2iF :
// CHECK-NOT:     [unknown]
// CHECK-LABEL: } // end sil function '$s1T8localVaryS2iF'
func localVar(_ n: Int) -> Int {
  var x = n
  let g = { x += 1 }
  g()
  return x
}

// DiagnoseStaticExclusivity reads the non-escaping closure's accesses, which
// are in the same component.
#if CONFLICT
func takesInoutAndNoEscapeClosure<T>(_ p: inout T, _ c: () -> ()) { }

func conflict() {
  var local = 5
  takesInoutAndNoEscapeClosure(&local) { // expected-error {{overlapping accesses to 'local', but modification requires exclusive access; consider copying to a local variable}}
    local = 8  // expected-note {{conflicting access is here}}
  }
}
#endif

// A local function and a closure that calls it form one component with their
// scope, in scan order.
// COMPONENT: [component] $s1T8siblingsSiyF: $s1T8siblingsSiyF $s1T8siblingsSiyFyyXEfU_ $s1T8siblingsSiyF4bumpL_yyF
func takesNoEscape(_ f: () -> ()) { f() }

func siblings() -> Int {
  var total = 0
  func bump() { total += 1 }
  takesNoEscape { bump() }
  bump()
  return total
}
