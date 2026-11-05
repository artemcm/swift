// Phase 6.2: on demand, the coordinator emits classes as legacy does: their
// initializers (the allocating and initializing entry points), destructors
// (destroying, deallocating, the ivar destroyer, the isolated deallocator),
// accessors, stored-property initializers, and property descriptors, in
// legacy order, and after each class's members its vtable, through
// SILVTableRequest. The output equals legacy's, whole module, single primary,
// and batch, with and without library evolution.
//
// Nothing references Plain: in whole-module mode its implicit init() is
// delayed, and only the vtable forces it. Derived overrides Base from another
// file, and one of its overrides needs a vtable thunk. Actors.swift is
// checked apart: its witness tables, Actor's included, wait for Phase 6.3.

// RUN: %empty-directory(%t)
// RUN: split-file %s %t

// Whole module.
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   %t/Classes.swift %t/Subclasses.swift %t/Uses.swift \
// RUN:   -o %t/wmo.legacy.sil
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   %t/Classes.swift %t/Subclasses.swift %t/Uses.swift \
// RUN:   -o %t/wmo.ondemand.sil -sil-verify-all -Xllvm -sil-on-demand-emission
// RUN: diff %t/wmo.legacy.sil %t/wmo.ondemand.sil
// RUN: %FileCheck %s < %t/wmo.ondemand.sil

// Each file as the single primary.
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   -primary-file %t/Classes.swift %t/Subclasses.swift %t/Uses.swift \
// RUN:   -o %t/Classes.legacy.sil
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   -primary-file %t/Classes.swift %t/Subclasses.swift %t/Uses.swift \
// RUN:   -o %t/Classes.ondemand.sil -Xllvm -sil-on-demand-emission
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   %t/Classes.swift -primary-file %t/Subclasses.swift %t/Uses.swift \
// RUN:   -o %t/Subclasses.legacy.sil
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   %t/Classes.swift -primary-file %t/Subclasses.swift %t/Uses.swift \
// RUN:   -o %t/Subclasses.ondemand.sil -Xllvm -sil-on-demand-emission
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   %t/Classes.swift %t/Subclasses.swift -primary-file %t/Uses.swift \
// RUN:   -o %t/Uses.legacy.sil
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   %t/Classes.swift %t/Subclasses.swift -primary-file %t/Uses.swift \
// RUN:   -o %t/Uses.ondemand.sil -Xllvm -sil-on-demand-emission
// RUN: diff %t/Classes.legacy.sil %t/Classes.ondemand.sil
// RUN: diff %t/Subclasses.legacy.sil %t/Subclasses.ondemand.sil
// RUN: diff %t/Uses.legacy.sil %t/Uses.ondemand.sil

// Batch, on demand: each output equals its single-primary output (F1).
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   -primary-file %t/Classes.swift -primary-file %t/Subclasses.swift \
// RUN:   -primary-file %t/Uses.swift -o %t/Classes.batch.sil \
// RUN:   -o %t/Subclasses.batch.sil -o %t/Uses.batch.sil \
// RUN:   -Xllvm -sil-on-demand-emission
// RUN: diff %t/Classes.batch.sil %t/Classes.ondemand.sil
// RUN: diff %t/Subclasses.batch.sil %t/Subclasses.ondemand.sil
// RUN: diff %t/Uses.batch.sil %t/Uses.ondemand.sil

// Library evolution: public classes are resilient.
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   -enable-library-evolution \
// RUN:   %t/Classes.swift %t/Subclasses.swift %t/Uses.swift \
// RUN:   -o %t/evolution.legacy.sil
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   -enable-library-evolution \
// RUN:   %t/Classes.swift %t/Subclasses.swift %t/Uses.swift \
// RUN:   -o %t/evolution.ondemand.sil -sil-verify-all \
// RUN:   -Xllvm -sil-on-demand-emission
// RUN: diff %t/evolution.legacy.sil %t/evolution.ondemand.sil

// One vtable request per class: Base, Box, IntBox, Plain, Holder.Nested,
// Derived.
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   %t/Classes.swift %t/Subclasses.swift %t/Uses.swift -o /dev/null \
// RUN:   -Xllvm -sil-on-demand-emission -analyze-request-evaluator 2>&1 \
// RUN:   | %FileCheck --check-prefix=REQUESTS %s
// REQUESTS: SILVTableRequest{{.*}} 6

// An actor and a @MainActor class with an isolated deinit.
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   %t/Actors.swift -o %t/actors.ondemand.sil -sil-verify-all \
// RUN:   -Xllvm -sil-on-demand-emission
// RUN: %FileCheck --check-prefix=ACTORS --implicit-check-not="Counter: Actor" \
// RUN:   %s < %t/actors.ondemand.sil
// ACTORS-DAG: sil [exact_self_class] @$s1M7CounterCACycfC : $@convention(method) (@thick Counter.Type) -> @owned Counter {
// ACTORS-DAG: sil @$s1M7CounterCACycfc : $@convention(method) (@owned Counter) -> @owned Counter {
// ACTORS-DAG: sil @$s1M6ScreenCfZ : $@convention(thin) (@owned Screen) -> () {
// ACTORS-DAG: sil_vtable Counter {
// ACTORS-DAG: sil_vtable Screen {

// Where on demand differs from legacy, by design. Leaf, a final subclass in
// another file than Base, modifies Base.tag: both paths devirtualize the call
// to its accessor, and on demand also inlines it, lowering the transparent
// accessor from the other file (Phase 4's cross-primary @_transparent
// inlining). Legacy has no body for it and keeps the call. The parity inputs
// above avoid such a call.
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   -primary-file %t/CrossFile.swift %t/Classes.swift \
// RUN:   -o %t/CrossFile.legacy.sil
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   -primary-file %t/CrossFile.swift %t/Classes.swift \
// RUN:   -o %t/CrossFile.ondemand.sil -Xllvm -sil-on-demand-emission
// RUN: %FileCheck --check-prefix=LEAF-LEGACY %s < %t/CrossFile.legacy.sil
// RUN: %FileCheck --check-prefix=LEAF-ONDEMAND %s < %t/CrossFile.ondemand.sil
// LEAF-LEGACY-LABEL: sil hidden @$s1M4LeafC4pokeyyF :
// LEAF-LEGACY: function_ref @$s1M4BaseC3tagSivM
// LEAF-LEGACY: } // end sil function '$s1M4LeafC4pokeyyF'
// LEAF-ONDEMAND-LABEL: sil hidden @$s1M4LeafC4pokeyyF :
// LEAF-ONDEMAND-NOT: function_ref @$s1M4BaseC3tagSivM
// LEAF-ONDEMAND: ref_element_addr {{%[0-9]+}}, #Base.tag
// LEAF-ONDEMAND: } // end sil function '$s1M4LeafC4pokeyyF'

// The diffs above aren't vacuous. Plain's initializer, which only the vtable
// references, has a body:
// CHECK-LABEL: sil hidden {{.*}}@$s1M5PlainCACycfC : {{.*}} {
// CHECK-LABEL: sil_vtable Base {
// CHECK:   #Base.init!allocator: {{.*}} : @$s1M4BaseC4nameACSS_tcfC
// CHECK:   #Base.deinit!deallocator: @$s1M4BaseCfD
// CHECK-LABEL: sil_vtable IntBox {
// CHECK:   #Box.init!allocator: {{.*}}TV [override]
// CHECK:   #Box.get: {{.*}}TV [override]
// CHECK-LABEL: sil_vtable Plain {
// CHECK:   #Plain.init!allocator: {{.*}} : @$s1M5PlainCACycfC
// CHECK-LABEL: sil_vtable Derived {
// CHECK:   #Base.describe: {{.*}}TV [override]
// CHECK:   #Derived!ivardestroyer: @$s1M7DerivedCfE

//--- Classes.swift
@propertyWrapper public struct Wrapped<T> {
  public var wrappedValue: T
  public init(wrappedValue: T) { self.wrappedValue = wrappedValue }
}

public class Base {
  public var tag: Int = 0
  public let name: String
  var observed: Int = 0 { didSet { tag &+= 1 } }
  lazy var cached: [Int] = [1, 2, 3]
  weak var peer: Base?
  @Wrapped var wrapped: Int = 5
  // A closure in a stored property's initializer, emitted into both
  // designated initializers (the audit case in Plans/Phase6-Plan.md).
  var fromClosure: Int = { 40 &+ 2 }()
  public init(name: String) { self.name = name }
  public convenience init() { self.init(name: "base") }
  public required init(copy other: Base) { self.name = other.name }
  public func describe() -> String? { return name }
  public func bump() { tag &+= 1 }
  public subscript(i: Int) -> Int {
    get { return tag &+ i }
    set { tag = newValue &- i }
  }
  public class func make() -> Self { return self.init(copy: Base(name: "m")) }
  deinit { tag = 0 }
}

extension Base {
  public convenience init(tag: Int) {
    self.init(name: "t")
    self.tag = tag
  }
  public var doubled: Int { return tag &* 2 }
  public func twice() { bump(); bump() }
}

open class Box<T> {
  open var value: T
  public init(_ v: T) { value = v }
  open func get() -> T { return value }
}

// Overriding a generic method and inheriting a generic initializer, with
// T == Int: two reabstracting vtable thunks.
public final class IntBox: Box<Int> {
  public override func get() -> Int { return value &+ 1 }
}

// Nothing references Plain: its implicit init() is delayed, and only the
// vtable forces it.
class Plain { var x = 0 }

struct Holder {
  class Nested { var y = 1 }
}

//--- Subclasses.swift
// An override of a class from another file.
public final class Derived: Base {
  var extra: [String] = []       // nontrivial: an ivar destroyer
  public override init(name: String) {
    super.init(name: name)
    extra.append(name)
  }
  public required init(copy other: Base) { super.init(copy: other) }
  // String? to String: the vtable entry needs a thunk.
  public override func describe() -> String { return "derived " + name }
  public override func bump() { super.bump() }
  override var observed: Int { didSet { extra.append("o") } }
}

//--- Uses.swift
public func use(_ b: Base) -> Int {
  b.bump()
  let c = type(of: b).init(copy: b)
  return c.tag &+ Base(tag: 3).doubled &+ IntBox(4).get()
}

//--- Actors.swift
public actor Counter {
  var count = 0
  public init() {}
  public func increment() -> Int {
    count += 1
    return count
  }
}

@MainActor public final class Screen {
  var title = ""
  public init() {}
  isolated deinit { title = "" }
}

//--- CrossFile.swift
final class Leaf: Base {
  func poke() { tag &+= 1 }
}
