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
// RUN:   -Xllvm -sil-on-demand-emission
// RUN: diff %t/Thunks.legacy.sil %t/Thunks.ondemand.sil
// RUN: diff %t/Uses.legacy.sil %t/Uses.ondemand.sil

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
