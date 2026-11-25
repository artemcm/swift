// Phase 6.6: on demand, a static stored property is a global, as on the
// legacy path: its sil_global, once-token, lazy initializer, and accessor,
// then its accessors and property descriptor. A struct's, an enum's, a final
// class's, and an extension's; a wrapped and an observed one; and, with
// library evolution, a resilient type's.

// RUN: %empty-directory(%t)
// RUN: split-file %s %t

// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   %t/Statics.swift %t/Use.swift -o %t/wmo.legacy.sil
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   %t/Statics.swift %t/Use.swift -o %t/wmo.ondemand.sil -sil-verify-all \
// RUN:   -Xllvm -sil-on-demand-emission
// RUN: %{python} %S/Inputs/sil_sort_external_entities.py M \
// RUN:   < %t/wmo.legacy.sil > %t/wmo.legacy.sorted.sil
// RUN: %{python} %S/Inputs/sil_sort_external_entities.py M \
// RUN:   < %t/wmo.ondemand.sil > %t/wmo.ondemand.sorted.sil
// RUN: diff %t/wmo.legacy.sorted.sil %t/wmo.ondemand.sorted.sil
// RUN: %FileCheck %s < %t/wmo.ondemand.sil

// RUN: %target-swift-frontend -c -parse-as-library -module-name M \
// RUN:   -primary-file %t/Statics.swift -primary-file %t/Use.swift \
// RUN:   -o %t/Statics.legacy.o -o %t/Use.legacy.o
// RUN: %target-swift-frontend -c -parse-as-library -module-name M \
// RUN:   -primary-file %t/Statics.swift -primary-file %t/Use.swift \
// RUN:   -o %t/Statics.ondemand.o -o %t/Use.ondemand.o -sil-verify-all \
// RUN:   -Xllvm -sil-on-demand-emission
// RUN: %llvm-nm --defined-only -j %t/Statics.legacy.o | sort > %t/Statics.legacy.defined
// RUN: %llvm-nm --defined-only -j %t/Statics.ondemand.o | sort > %t/Statics.ondemand.defined
// RUN: diff %t/Statics.legacy.defined %t/Statics.ondemand.defined
// RUN: %llvm-nm --undefined-only -j %t/Statics.legacy.o | sort > %t/Statics.legacy.undefined
// RUN: %llvm-nm --undefined-only -j %t/Statics.ondemand.o | sort > %t/Statics.ondemand.undefined
// RUN: diff %t/Statics.legacy.undefined %t/Statics.ondemand.undefined
// RUN: %llvm-nm --defined-only -j %t/Use.legacy.o | sort > %t/Use.legacy.defined
// RUN: %llvm-nm --defined-only -j %t/Use.ondemand.o | sort > %t/Use.ondemand.defined
// RUN: diff %t/Use.legacy.defined %t/Use.ondemand.defined

// At -O, legacy delays the accessor of an implicit private global, such as a
// private wrapped property's backing storage, until a body references it, and
// then emits it. On demand the coordinator must emit it too: before, the
// object referenced it as an undefined private symbol.
// RUN: %target-swift-frontend -c -parse-as-library -module-name M -O \
// RUN:   -primary-file %t/Wrapped.swift -primary-file %t/WrappedUse.swift \
// RUN:   -o %t/Wrapped.legacy.o -o %t/WrappedUse.legacy.o
// RUN: %target-swift-frontend -c -parse-as-library -module-name M -O \
// RUN:   -primary-file %t/Wrapped.swift -primary-file %t/WrappedUse.swift \
// RUN:   -o %t/Wrapped.ondemand.o -o %t/WrappedUse.ondemand.o -sil-verify-all \
// RUN:   -Xllvm -sil-on-demand-emission
// RUN: %llvm-nm --undefined-only -j %t/Wrapped.legacy.o | sort > %t/Wrapped.legacy.undefined
// RUN: %llvm-nm --undefined-only -j %t/Wrapped.ondemand.o | sort > %t/Wrapped.ondemand.undefined
// RUN: diff %t/Wrapped.legacy.undefined %t/Wrapped.ondemand.undefined
// RUN: %llvm-nm --defined-only -j %t/Wrapped.legacy.o | sort > %t/Wrapped.legacy.defined
// RUN: %llvm-nm --defined-only -j %t/Wrapped.ondemand.o | sort > %t/Wrapped.ondemand.defined
// RUN: diff %t/Wrapped.legacy.defined %t/Wrapped.ondemand.defined
// And in whole-module mode, where an internal implicit global is delayable too.
// RUN: %target-swift-frontend -c -parse-as-library -module-name M -O \
// RUN:   %t/Wrapped.swift %t/WrappedUse.swift -o %t/WrappedWMO.legacy.o
// RUN: %target-swift-frontend -c -parse-as-library -module-name M -O \
// RUN:   %t/Wrapped.swift %t/WrappedUse.swift -o %t/WrappedWMO.ondemand.o \
// RUN:   -sil-verify-all -Xllvm -sil-on-demand-emission
// RUN: %llvm-nm -j %t/WrappedWMO.legacy.o | sort > %t/WrappedWMO.legacy.syms
// RUN: %llvm-nm -j %t/WrappedWMO.ondemand.o | sort > %t/WrappedWMO.ondemand.syms
// RUN: diff %t/WrappedWMO.legacy.syms %t/WrappedWMO.ondemand.syms

// Resilient types.
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   -enable-library-evolution %t/Resilient.swift -o %t/res.legacy.sil
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   -enable-library-evolution %t/Resilient.swift -o %t/res.ondemand.sil \
// RUN:   -sil-verify-all -Xllvm -sil-on-demand-emission
// RUN: %{python} %S/Inputs/sil_sort_external_entities.py M \
// RUN:   < %t/res.legacy.sil > %t/res.legacy.sorted.sil
// RUN: %{python} %S/Inputs/sil_sort_external_entities.py M \
// RUN:   < %t/res.ondemand.sil > %t/res.ondemand.sorted.sil
// RUN: diff %t/res.legacy.sorted.sil %t/res.ondemand.sorted.sil
// RUN: %FileCheck --check-prefix=RES %s < %t/res.ondemand.sil

// CHECK-DAG: sil_global hidden @$s1M1SV5countSivpZ : $Int = {
// CHECK-DAG: sil hidden [global_init] @$s1M1SV5countSivau : $@convention(thin) () -> Builtin.RawPointer {
// CHECK-DAG: sil_global hidden [let] @$s1M1SV6sharedACvpZ : $S
// CHECK-DAG: sil private [global_init_once_fn] @$s1M1SV6shared_WZ : $@convention(c) (Builtin.RawPointer) -> () {
// CHECK-DAG: sil_global hidden [let] @$s1M1EO3allSayACGvpZ : $Array<E>
// CHECK-DAG: sil_global hidden @$s1M1CC4nameSSvpZ : $String
// CHECK-DAG: sil_global hidden [let] @$s1M1SV13fromExtensionSSvpZ : $String
// CHECK-DAG: sil private [global_init] @$s1M1SV6_level{{.*}}AA5ClampVvau : $@convention(thin) () -> Builtin.RawPointer {
// CHECK-DAG: sil private @$s1M1SV7watchedSivWZ : $@convention(method) (Int, @thin S.Type) -> () {
// RES-DAG: sil_global private @$s1M1RV5countSivpZ : $Int = {
// RES-DAG: sil_global private [let] @$s1M1RV6sharedACvpZ : $R

//--- Statics.swift
@propertyWrapper struct Clamp {
  var v: Int
  init(wrappedValue: Int) { v = min(wrappedValue, 10) }
  var wrappedValue: Int { get { v } set { v = min(newValue, 10) } }
}
struct S {
  static var count = 0
  static let shared = S(tag: "shared")
  static let k = 7
  @Clamp static var level = 50
  static var watched = 0 { didSet { print("watched", oldValue, "->", watched) } }
  var tag: String
}
enum E { case a, b; static let all: [E] = [.a, .b] }
final class C { static var name = "C" }
extension S { static let fromExtension = "ext" }

//--- Use.swift
func touch() -> String {
  S.count += 1
  S.level += 5
  S.watched = 2
  return "\(S.count) \(S.shared.tag) \(S.k) \(S.level) \(E.all.count) \(C.name) \(S.fromExtension)"
}

//--- Resilient.swift
public struct R {
  public static var count = 0
  public static let shared = R(v: 9)
  public var v: Int
  public init(v: Int) { self.v = v }
}
public func use() -> Int { R.count += 1; return R.count + R.shared.v }

//--- Wrapped.swift
@propertyWrapper struct Limit {
  var v: Int
  init(wrappedValue: Int) { v = min(wrappedValue, 10) }
  var wrappedValue: Int { get { v } set { v = min(newValue, 10) } }
}
struct W {
  @Limit private static var p = 1
  @Limit static var q = 2
  @inline(never) static func f() -> Int { p += 1; return p }
}

//--- WrappedUse.swift
@inline(never) public func touchW() -> Int { W.q += 1; return W.f() + W.q }
