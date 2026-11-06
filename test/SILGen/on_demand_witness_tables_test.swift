// Phase 6.3: on demand, the coordinator emits the witness tables of the types
// and extensions of the files being emitted, as legacy does, through
// SILWitnessTableRequest: after a type's members and its other tables, and
// after an extension's members. Each table brings its witness thunks, and
// the thunks force the delayed bodies they call (a derived conformance's
// __derived_enum_equals, hash(into:), CodingKeys). Before 6.3 on demand
// emitted no table, and a -c object silently lacked every conformance (D17).
//
// The table and thunk sets of both paths are compared, whole module and per
// primary in batch mode, and so are the symbols of batch -c objects. The
// thunks' text is checked in on_demand_witness_thunks_test.swift.

// RUN: %empty-directory(%t)
// RUN: split-file %s %t

// Whole module.
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   %t/Types.swift %t/Extensions.swift %t/Uses.swift -o %t/wmo.legacy.sil
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   %t/Types.swift %t/Extensions.swift %t/Uses.swift -o %t/wmo.ondemand.sil \
// RUN:   -sil-verify-all -Xllvm -sil-on-demand-emission
// RUN: grep -E '^sil_(default_)?witness_table' %t/wmo.legacy.sil | sort > %t/wmo.legacy.tables
// RUN: grep -E '^sil_(default_)?witness_table' %t/wmo.ondemand.sil | sort > %t/wmo.ondemand.tables
// RUN: diff %t/wmo.legacy.tables %t/wmo.ondemand.tables
// RUN: grep -oE '^sil .*@\$s[^ ]*TW ' %t/wmo.legacy.sil | sort > %t/wmo.legacy.thunks
// RUN: grep -oE '^sil .*@\$s[^ ]*TW ' %t/wmo.ondemand.sil | sort > %t/wmo.ondemand.thunks
// RUN: diff %t/wmo.legacy.thunks %t/wmo.ondemand.thunks
// RUN: %FileCheck --check-prefix=TABLES %s < %t/wmo.ondemand.tables

// Batch mode: every file a primary, -emit-sil and -c.
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   -primary-file %t/Types.swift -primary-file %t/Extensions.swift \
// RUN:   -primary-file %t/Uses.swift -o %t/Types.legacy.sil \
// RUN:   -o %t/Extensions.legacy.sil -o %t/Uses.legacy.sil
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   -primary-file %t/Types.swift -primary-file %t/Extensions.swift \
// RUN:   -primary-file %t/Uses.swift -o %t/Types.ondemand.sil \
// RUN:   -o %t/Extensions.ondemand.sil -o %t/Uses.ondemand.sil \
// RUN:   -Xllvm -sil-on-demand-emission
// RUN: grep -E '^sil_witness_table' %t/Types.legacy.sil | sort > %t/Types.legacy.tables
// RUN: grep -E '^sil_witness_table' %t/Types.ondemand.sil | sort > %t/Types.ondemand.tables
// RUN: diff %t/Types.legacy.tables %t/Types.ondemand.tables
// RUN: grep -E '^sil_witness_table' %t/Extensions.legacy.sil | sort > %t/Extensions.legacy.tables
// RUN: grep -E '^sil_witness_table' %t/Extensions.ondemand.sil | sort > %t/Extensions.ondemand.tables
// RUN: diff %t/Extensions.legacy.tables %t/Extensions.ondemand.tables
// RUN: %FileCheck --check-prefix=EXTENSIONS %s < %t/Extensions.ondemand.tables

// RUN: %target-swift-frontend -c -parse-as-library -module-name M \
// RUN:   -primary-file %t/Types.swift -primary-file %t/Extensions.swift \
// RUN:   -primary-file %t/Uses.swift -o %t/Types.legacy.o \
// RUN:   -o %t/Extensions.legacy.o -o %t/Uses.legacy.o
// RUN: %target-swift-frontend -c -parse-as-library -module-name M \
// RUN:   -primary-file %t/Types.swift -primary-file %t/Extensions.swift \
// RUN:   -primary-file %t/Uses.swift -o %t/Types.ondemand.o \
// RUN:   -o %t/Extensions.ondemand.o -o %t/Uses.ondemand.o \
// RUN:   -Xllvm -sil-on-demand-emission
// RUN: %llvm-nm --defined-only -j %t/Types.legacy.o | sort > %t/Types.legacy.defined
// RUN: %llvm-nm --defined-only -j %t/Types.ondemand.o | sort > %t/Types.ondemand.defined
// RUN: diff %t/Types.legacy.defined %t/Types.ondemand.defined
// RUN: %llvm-nm --undefined-only -j %t/Types.legacy.o | sort > %t/Types.legacy.undefined
// RUN: %llvm-nm --undefined-only -j %t/Types.ondemand.o | sort > %t/Types.ondemand.undefined
// RUN: diff %t/Types.legacy.undefined %t/Types.ondemand.undefined
// RUN: %llvm-nm --defined-only -j %t/Extensions.legacy.o | sort > %t/Extensions.legacy.defined
// RUN: %llvm-nm --defined-only -j %t/Extensions.ondemand.o | sort > %t/Extensions.ondemand.defined
// RUN: diff %t/Extensions.legacy.defined %t/Extensions.ondemand.defined
// RUN: %llvm-nm --undefined-only -j %t/Uses.legacy.o | sort > %t/Uses.legacy.undefined
// RUN: %llvm-nm --undefined-only -j %t/Uses.ondemand.o | sort > %t/Uses.ondemand.undefined
// RUN: diff %t/Uses.legacy.undefined %t/Uses.ondemand.undefined

// One table request per conformance that M declares, each evaluated once:
// 32, of which 12 are to marker protocols (Sendable, SendableMetatype,
// BitwiseCopyable) and give no table, as on the legacy path. The two tables
// of Swift in the output are deserialized.
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   %t/Types.swift %t/Extensions.swift %t/Uses.swift -o /dev/null \
// RUN:   -Xllvm -sil-on-demand-emission -analyze-request-evaluator 2>&1 \
// RUN:   | %FileCheck --check-prefix=REQUESTS %s
// REQUESTS: SILWitnessTableRequest{{.*}} 32

// The diffs aren't vacuous.
// TABLES-DAG: sil_witness_table hidden <T where T : Named> Box<T>: Named module M {
// TABLES-DAG: sil_witness_table hidden <Element where Element : Named> Array<Element>: Named module M {
// TABLES-DAG: sil_witness_table hidden Counter: Actor module M {
// TABLES-DAG: sil_witness_table hidden Counter: Ticking module M {
// TABLES-DAG: sil_witness_table hidden Point: Decodable module M {
// TABLES-DAG: sil_witness_table hidden Shade: Hashable module M {
// TABLES-DAG: sil_witness_table hidden Shade: RawRepresentable module M {
// TABLES-DAG: sil_witness_table hidden Wheel: HasInner module M {
// EXTENSIONS: sil_witness_table hidden Point: CustomStringConvertible module M {
// EXTENSIONS-NEXT: sil_witness_table hidden Wheel: Named module M {

//--- Types.swift
protocol Named { var name: String { get } }
protocol HasInner { associatedtype Inner: Named; var inner: Inner { get } }
protocol Ticking { func tick() async -> Int }

struct Box<T: Named>: Named { var t: T; var name: String { "Box(\(t.name))" } }
struct Wheel: HasInner { var inner: Box<Wheel> { Box(t: self) } }
extension Array: Named where Element: Named {
  var name: String { map(\.name).joined(separator: ",") }
}

struct Point: Codable, Hashable { var x: Int; var y: Int }
enum Shade: String, CaseIterable, Hashable { case light, dark }

actor Counter: Ticking { var n = 0; func tick() -> Int { n += 1; return n } }

//--- Extensions.swift
extension Point: CustomStringConvertible { var description: String { "(\(x), \(y))" } }
extension Wheel: Named { var name: String { "wheel" } }

//--- Uses.swift
func describe(_ n: some Named) -> String { n.name }
func hashes(_ p: Point, _ s: Shade) -> Bool { p.hashValue == s.hashValue }
func tick(_ t: any Ticking) async -> Int { await t.tick() }
