// Phase 6.3: on demand, the coordinator emits protocols and protocol
// extensions as legacy does. A resilient protocol gets its default witness
// table, and the members of a protocol extension (initializers that delegate
// to a requirement, properties, static members, subscripts, members of
// constrained extensions) are emitted whether or not anything references
// them, so their bodies are diagnosed. Before 6.3 the seeder skipped both,
// and an error in an unreferenced protocol extension member went unreported.

// RUN: %empty-directory(%t)
// RUN: split-file %s %t

// The members, whole module and in batch mode.
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   %t/Members.swift %t/Uses.swift -o %t/wmo.legacy.sil
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   %t/Members.swift %t/Uses.swift -o %t/wmo.ondemand.sil -sil-verify-all \
// RUN:   -Xllvm -sil-on-demand-emission
// RUN: diff %t/wmo.legacy.sil %t/wmo.ondemand.sil
// RUN: %FileCheck --check-prefix=MEMBERS %s < %t/wmo.ondemand.sil
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   -primary-file %t/Members.swift -primary-file %t/Uses.swift \
// RUN:   -o %t/Members.legacy.sil -o %t/Uses.legacy.sil
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   -primary-file %t/Members.swift -primary-file %t/Uses.swift \
// RUN:   -o %t/Members.ondemand.sil -o %t/Uses.ondemand.sil \
// RUN:   -Xllvm -sil-on-demand-emission
// RUN: diff %t/Members.legacy.sil %t/Members.ondemand.sil

// A resilient protocol's default witness table.
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   -enable-library-evolution %t/Resilient.swift -o %t/res.legacy.sil
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   -enable-library-evolution %t/Resilient.swift -o %t/res.ondemand.sil \
// RUN:   -sil-verify-all -Xllvm -sil-on-demand-emission
// RUN: grep -A4 '^sil_default_witness_table' %t/res.legacy.sil > %t/res.legacy.tables
// RUN: grep -A4 '^sil_default_witness_table' %t/res.ondemand.sil > %t/res.ondemand.tables
// RUN: diff %t/res.legacy.tables %t/res.ondemand.tables
// RUN: %FileCheck --check-prefix=DEFAULT %s < %t/res.ondemand.tables

// The diagnostics of protocol extension members, on both paths.
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   %t/DI.swift -o /dev/null -verify
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   %t/DI.swift -o /dev/null -verify -Xllvm -sil-on-demand-emission

// MEMBERS-DAG: sil hidden @$s1M5ShapePAAE5twicexx_tcfC :
// MEMBERS-DAG: sil hidden @$s1M5ShapePAAE8triangle{{.*}}FZ :
// MEMBERS-DAG: sil hidden @$s1M5ShapePAAEyS2icig :
// MEMBERS-DAG: sil hidden @$s1M5ShapePAAE11descriptionSSvg :
// MEMBERS-DAG: sil hidden @$s1M5ShapePA2A7MutableRzrlE4bumpyyF :
// MEMBERS-DAG: sil hidden @$s1M5ShapePAAE6unused{{.*}}F :

// DEFAULT: sil_default_witness_table Res {
// DEFAULT-NEXT:   no_default
// DEFAULT-NEXT:   method #Res.withDefault: {{.*}} : @$s1M3ResP11withDefaultSiyF

//--- Members.swift
protocol Shape { var sides: Int { get }; init(sides: Int) }
protocol Mutable { mutating func setSides(_ n: Int) }
extension Shape {
  init(twice other: Self) { self.init(sides: other.sides * 2) }
  var description: String { "shape with \(sides) sides" }
  static func triangle() -> Self { Self(sides: 3) }
  subscript(i: Int) -> Int { sides + i }
  func unused() -> Int { var s = sides; s += 1; return s }
}
extension Shape where Self: Mutable {
  mutating func bump() { setSides(sides + 1) }
}

//--- Uses.swift
func make<S: Shape>(_: S.Type) -> String { S.triangle().description }

//--- Resilient.swift
public protocol Res { func req() -> Int; func withDefault() -> Int }
extension Res { public func withDefault() -> Int { req() * 10 } }

//--- DI.swift
protocol Polygon { init(sides: Int); var sides: Int { get } }
extension Polygon {
  init(never: Int) {
  } // expected-error {{'self.init' isn't called on all paths before returning from initializer}}
  init(early: Int) {
    _ = self.sides // expected-error {{'self' used before 'self.init' call or assignment to 'self'}}
    self.init(sides: early)
  }
  init(fine: Int) { self.init(sides: fine) }
  func area() -> Int { let x: Int; return x } // expected-error {{constant 'x' used before being initialized}} expected-note {{constant defined here}}
}
