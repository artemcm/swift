// Under -experimental-lazy-typecheck, legacy emits no function body once an
// error has been diagnosed: shouldEmitFunctionBody type-checks the body, and
// declines all of them after the first error. Legacy asks where it visits a
// declaration. On demand, a body that nothing visited is still requested
// through two other paths:
//
// - The coordinator's scan of an emitted body queues the functions it
//   references. A class's allocator references its initializer, and its
//   deallocator the destroying destructor.
// - The mandatory inliner canonicalizes a transparent callee that has no body
//   yet. A default-argument generator, which legacy emits whatever the error
//   state, can call a transparent function that legacy declined.
//
// Emitting such a body crashed in a class initializer's prolog (InitError),
// and reported the SIL diagnostics of a body that legacy leaves out
// (AfterError and InlinerAfterError). SILFunctionBodyRequest now asks the same
// gate, so a declined body stays a declaration. A function that was delayed
// and then forced passed the gate when it was delayed, and legacy emits it
// whatever the error state (ForcedAfterError).

// REQUIRES: asserts

// RUN: %empty-directory(%t)
// RUN: split-file %s %t

// RUN: %target-swift-frontend -emit-sil -parse-as-library \
// RUN:   -enable-library-evolution -module-name Test \
// RUN:   -experimental-lazy-typecheck -verify %t/InitError.swift -o /dev/null
// RUN: %target-swift-frontend -emit-sil -parse-as-library \
// RUN:   -enable-library-evolution -module-name Test \
// RUN:   -experimental-lazy-typecheck -verify %t/InitError.swift -o /dev/null \
// RUN:   -Xllvm -sil-on-demand-emission

// RUN: %target-swift-frontend -emit-sil -parse-as-library \
// RUN:   -enable-library-evolution -module-name Test \
// RUN:   -experimental-lazy-typecheck -verify %t/AfterError.swift -o /dev/null
// RUN: %target-swift-frontend -emit-sil -parse-as-library \
// RUN:   -enable-library-evolution -module-name Test \
// RUN:   -experimental-lazy-typecheck -verify %t/AfterError.swift \
// RUN:   -o /dev/null -Xllvm -sil-on-demand-emission

// RUN: %target-swift-frontend -emit-sil -parse-as-library \
// RUN:   -enable-library-evolution -module-name Test \
// RUN:   -experimental-lazy-typecheck -verify %t/InlinerAfterError.swift \
// RUN:   -o /dev/null
// RUN: %target-swift-frontend -emit-sil -parse-as-library \
// RUN:   -enable-library-evolution -module-name Test \
// RUN:   -experimental-lazy-typecheck -verify %t/InlinerAfterError.swift \
// RUN:   -o /dev/null -Xllvm -sil-on-demand-emission

// RUN: %target-swift-frontend -emit-sil -parse-as-library \
// RUN:   -enable-library-evolution -module-name Test \
// RUN:   -experimental-lazy-typecheck -verify %t/NoError.swift -o /dev/null
// RUN: %target-swift-frontend -emit-sil -parse-as-library \
// RUN:   -enable-library-evolution -module-name Test \
// RUN:   -experimental-lazy-typecheck -verify %t/NoError.swift -o /dev/null \
// RUN:   -Xllvm -sil-on-demand-emission

// RUN: %target-swift-frontend -emit-sil -parse-as-library \
// RUN:   -enable-library-evolution -module-name Test \
// RUN:   -experimental-lazy-typecheck -verify %t/ForcedAfterError.swift \
// RUN:   -o /dev/null
// RUN: %target-swift-frontend -emit-sil -parse-as-library \
// RUN:   -enable-library-evolution -module-name Test \
// RUN:   -experimental-lazy-typecheck -verify %t/ForcedAfterError.swift \
// RUN:   -o /dev/null -Xllvm -sil-on-demand-emission

// The request trace names the bodies that on demand declined, and the forced
// function that it didn't.
// RUN: %target-swift-frontend -emit-sil -parse-as-library \
// RUN:   -enable-library-evolution -module-name Test \
// RUN:   -experimental-lazy-typecheck -verify %t/AfterError.swift \
// RUN:   -o /dev/null -Xllvm -sil-on-demand-emission \
// RUN:   -Xllvm -debug-only=silgen-requests 2>&1 \
// RUN:   | %FileCheck --check-prefix=AFTER %s
// RUN: %target-swift-frontend -emit-sil -parse-as-library \
// RUN:   -enable-library-evolution -module-name Test \
// RUN:   -experimental-lazy-typecheck -verify %t/InlinerAfterError.swift \
// RUN:   -o /dev/null -Xllvm -sil-on-demand-emission \
// RUN:   -Xllvm -debug-only=silgen-requests 2>&1 \
// RUN:   | %FileCheck --check-prefix=INLINER %s
// RUN: %target-swift-frontend -emit-sil -parse-as-library \
// RUN:   -enable-library-evolution -module-name Test \
// RUN:   -experimental-lazy-typecheck -verify %t/ForcedAfterError.swift \
// RUN:   -o /dev/null -Xllvm -sil-on-demand-emission \
// RUN:   -Xllvm -debug-only=silgen-requests 2>&1 \
// RUN:   | %FileCheck --check-prefix=FORCED --implicit-check-not='[declined]' %s

//--- InitError.swift

// SIL diagnostics should not crash on invalid types. This is the input of
// test/SIL/lazy_typecheck.swift. The coordinator's scan of the allocator
// queued the initializer, which the seeder had declined.
final class C {
  private let x: Nonexistent // expected-error {{cannot find type 'Nonexistent' in scope}}

  init(x: Nonexistent) { // expected-error {{cannot find type 'Nonexistent' in scope}}
    self.x = x
  }
}

//--- AfterError.swift

// Legacy emits neither body once the error is diagnosed. The uninitialized
// constants would be errors if it did.

func uses(_ v: Nonexistent) {} // expected-error {{cannot find type 'Nonexistent' in scope}}

final class D {
  init() {
    let z: Int
    _ = z
  }
  deinit {
    let y: Int
    _ = y
  }
}

// AFTER-DAG: [declined] #D.init!initializer
// AFTER-DAG: [declined] #D.deinit!destroyer

//--- InlinerAfterError.swift

// The default-argument generator of g is emitted, and calls a transparent
// function that the gate declines. The inliner asks for its body.

func uses(_ v: Nonexistent) {} // expected-error {{cannot find type 'Nonexistent' in scope}}

@_transparent public func t() -> Int {
  let y: Int
  return y
}

public func g(x: Int = t()) {}

// INLINER: [declined] #t

//--- NoError.swift

// The control: without the error, every body is emitted and diagnosed.

final class D {
  init() {
    let z: Int // expected-note {{constant defined here}}
    _ = z // expected-error {{constant 'z' used before being initialized}}
  }
  deinit {
    let y: Int // expected-note {{constant defined here}}
    _ = y // expected-error {{constant 'y' used before being initialized}}
  }
}

//--- ForcedAfterError.swift

// The control for the gate's exemption: f is emitted before the error, and
// references the implicit initializer of S, which is forced. Legacy emits it,
// so the gate doesn't decline it, though the error has been diagnosed by the
// time on demand reaches it.

struct S { var a = 1 }

func f() -> S { return S() }

func uses(_ v: Nonexistent) {} // expected-error {{cannot find type 'Nonexistent' in scope}}

// FORCED: [worklist] processing: #S.init!allocator
