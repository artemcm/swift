// Phase 6.3: on demand, every witness thunk runs the mandatory pipeline, as
// on the legacy path. SILGenModule::emitProtocolWitness creates a thunk with
// no SILDeclRef, which the coordinator's sweep doesn't reach; without
// canonicalizeSynthesizedOnDemand its raw body was advanced to canonical
// unchanged. Legacy's mandatory inlining devirtualizes a class_method that a
// thunk calls when the class's vtable allows it: an actor's method, and a
// method of an open class that no subclass overrides. Thunks created while
// the seeder runs are canonicalized after it, when every vtable exists.

// RUN: %empty-directory(%t)
// RUN: split-file %s %t

// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   %t/Thunks.swift %t/Uses.swift -o %t/wmo.legacy.sil
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   %t/Thunks.swift %t/Uses.swift -o %t/wmo.ondemand.sil -sil-verify-all \
// RUN:   -Xllvm -sil-on-demand-emission
// RUN: diff %t/wmo.legacy.sil %t/wmo.ondemand.sil
// RUN: %FileCheck %s < %t/wmo.ondemand.sil

// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   -primary-file %t/Thunks.swift -primary-file %t/Uses.swift \
// RUN:   -o %t/Thunks.legacy.sil -o %t/Uses.legacy.sil
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   -primary-file %t/Thunks.swift -primary-file %t/Uses.swift \
// RUN:   -o %t/Thunks.ondemand.sil -o %t/Uses.ondemand.sil \
// RUN:   -sil-verify-all -Xllvm -sil-on-demand-emission
// RUN: diff %t/Thunks.legacy.sil %t/Thunks.ondemand.sil
// RUN: diff %t/Uses.legacy.sil %t/Uses.ondemand.sil

// A thunk created while the seeder runs can use a conformance that the Clang
// importer synthesizes: here it applies f<CTone>, with CTone: Hashable. The
// coordinator drains pendingConformances before it canonicalizes the thunks,
// so their linker finds the tables.
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   -I %t/inc %t/Imported.swift -o %t/imp.legacy.sil
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   -I %t/inc %t/Imported.swift -o %t/imp.ondemand.sil -sil-verify-all \
// RUN:   -Xllvm -sil-on-demand-emission
// RUN: %{python} %S/Inputs/sil_sort_external_entities.py M \
// RUN:   < %t/imp.legacy.sil > %t/imp.legacy.sorted.sil
// RUN: %{python} %S/Inputs/sil_sort_external_entities.py M \
// RUN:   < %t/imp.ondemand.sil > %t/imp.ondemand.sorted.sil
// RUN: diff %t/imp.legacy.sorted.sil %t/imp.ondemand.sorted.sil
// RUN: %FileCheck --check-prefix=IMPORTED %s < %t/imp.ondemand.sil
// IMPORTED-DAG: sil_witness_table shared CTone: Hashable module CTones {
// IMPORTED-DAG: sil_witness_table hidden SF: PF module M {

// CHECK-LABEL: sil private [transparent] [thunk] @$s1M3ActCAA5TicksA2aDP4tickSiyYaFTW :
// CHECK-NOT:     class_method
// CHECK:         function_ref @$s1M3ActC4tickSiyF
// CHECK-LABEL: } // end sil function '$s1M3ActCAA5TicksA2aDP4tickSiyYaFTW'
// CHECK-LABEL: sil private [transparent] [thunk] @$s1M4OpenCAA5TicksA2aDP4tickSiyYaFTW :
// CHECK-NOT:     class_method
// CHECK:         function_ref @$s1M4OpenC4tickSiyF
// CHECK-LABEL: } // end sil function '$s1M4OpenCAA5TicksA2aDP4tickSiyYaFTW'

//--- Thunks.swift
protocol Ticks { func tick() async -> Int }
final class Final: Ticks { func tick() -> Int { 1 } }
actor Act: Ticks { func tick() -> Int { 2 } }
class Open: Ticks { func tick() -> Int { 3 }; func other() -> Int { 4 } }
final class Sub: Open { override func other() -> Int { 5 } }
struct Plain: Ticks { func tick() -> Int { 6 } }

//--- Uses.swift
func ticks(_ t: [any Ticks]) async -> Int {
  var n = 0
  for x in t { n += await x.tick() }
  return n
}

//--- inc/module.modulemap
module CTones { header "tones.h" export * }

//--- inc/tones.h
typedef enum __attribute__((enum_extensibility(open))) CTone : int { CLow, CHigh } CTone;

//--- Imported.swift
import CTones
protocol PF { func f(_: CTone) }
struct SF: PF { func f<T: Hashable>(_: T) {} }
