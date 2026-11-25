// D10: on demand, a body that references a function legacy leaves without a
// body made the coordinator queue it, and emitting it aborted. That function
// is either declared without a body, like an @_silgen_name declaration of a C
// function, or has its body skipped
// (-experimental-skip-non-inlinable-function-bodies). Each entry point that
// emits a declaration's body has the problem: a function, a class's
// initializing entry point and destroying destructor, and a struct's
// allocating entry point.

// RUN: %empty-directory(%t)
// RUN: split-file %s %t

// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   %t/BodyLess.swift -o %t/body-less.legacy.sil
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   %t/BodyLess.swift -o %t/body-less.ondemand.sil -sil-verify-all \
// RUN:   -Xllvm -sil-on-demand-emission
// RUN: diff %t/body-less.legacy.sil %t/body-less.ondemand.sil
// RUN: %FileCheck --check-prefix=BODYLESS %s < %t/body-less.ondemand.sil

// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   %t/Skipped.swift -experimental-skip-non-inlinable-function-bodies \
// RUN:   -o %t/skipped.legacy.sil
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   %t/Skipped.swift -experimental-skip-non-inlinable-function-bodies \
// RUN:   -o %t/skipped.ondemand.sil -Xllvm -sil-on-demand-emission
// RUN: diff %t/skipped.legacy.sil %t/skipped.ondemand.sil
// RUN: %FileCheck --check-prefix=SKIPPED %s < %t/skipped.ondemand.sil

// BODYLESS-LABEL: sil hidden @$s1M4stopyyF :
// BODYLESS: function_ref @exit
// BODYLESS: {{^}}sil hidden_external @exit : $@convention(thin) (Int32) -> Never{{$}}

// The diff above isn't vacuous: on demand, the inlinable body is emitted, and
// the skipped ones are declarations.
// SKIPPED-LABEL: sil {{.*}}@$s1M1fSiyF : $@convention(thin) () -> Int {
// SKIPPED-DAG: {{^}}sil @$s1M1gSiyF : $@convention(thin) () -> Int{{$}}
// SKIPPED-DAG: {{^}}sil @$s1M1KCyACSicfc : $@convention(method) (Int, @owned K) -> @owned K{{$}}
// SKIPPED-DAG: {{^}}sil @$s1M1PV1xACSi_tcfC : $@convention(method) (Int, @thin P.Type) -> P{{$}}

//--- BodyLess.swift
@_silgen_name("exit") func exit(_: Int32) -> Never

func stop() { exit(0) }

//--- Skipped.swift
@inlinable public func f() -> Int { return g() &+ K(1).v &+ P(x: 2).x }
@usableFromInline internal func g() -> Int { return 42 }

@usableFromInline internal final class K {
  @usableFromInline var v: Int
  @usableFromInline init(_ v: Int) { self.v = v }
  deinit { v = 0 }
}

public struct P {
  public var x: Int
  @usableFromInline init(x: Int) { self.x = x }
}
