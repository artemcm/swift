// Phase 6.6 resolves D8 for library-mode globals: on demand, each global of
// the files being compiled gets what legacy gives it: its sil_global, its
// once-token and lazy initializer (emitGlobalInitialization), and its
// accessor, emitted through the request chain. A global of another primary
// stays a declaration in this one's output, as on the legacy path, so the
// objects define and reference the same symbols. A private global's accessor
// isn't delayed at -Onone (legacy emits it even unreferenced); the delayed
// case, at -O, is in on_demand_static_properties_test.swift.

// RUN: %empty-directory(%t)
// RUN: split-file %s %t

// Whole module.
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   %t/Globals.swift %t/Use.swift -o %t/wmo.legacy.sil
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   %t/Globals.swift %t/Use.swift -o %t/wmo.ondemand.sil -sil-verify-all \
// RUN:   -Xllvm -sil-on-demand-emission
// RUN: %{python} %S/Inputs/sil_sort_external_entities.py M \
// RUN:   < %t/wmo.legacy.sil > %t/wmo.legacy.sorted.sil
// RUN: %{python} %S/Inputs/sil_sort_external_entities.py M \
// RUN:   < %t/wmo.ondemand.sil > %t/wmo.ondemand.sorted.sil
// RUN: diff %t/wmo.legacy.sorted.sil %t/wmo.ondemand.sorted.sil
// RUN: %FileCheck %s < %t/wmo.ondemand.sil

// Batch mode: the SIL of each primary, and the symbols of each object.
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   -primary-file %t/Globals.swift -primary-file %t/Use.swift \
// RUN:   -o %t/Globals.legacy.sil -o %t/Use.legacy.sil
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   -primary-file %t/Globals.swift -primary-file %t/Use.swift \
// RUN:   -o %t/Globals.ondemand.sil -o %t/Use.ondemand.sil -sil-verify-all \
// RUN:   -Xllvm -sil-on-demand-emission
// RUN: %{python} %S/Inputs/sil_sort_external_entities.py M \
// RUN:   < %t/Globals.legacy.sil > %t/Globals.legacy.sorted.sil
// RUN: %{python} %S/Inputs/sil_sort_external_entities.py M \
// RUN:   < %t/Globals.ondemand.sil > %t/Globals.ondemand.sorted.sil
// RUN: diff %t/Globals.legacy.sorted.sil %t/Globals.ondemand.sorted.sil
// RUN: %{python} %S/Inputs/sil_sort_external_entities.py M \
// RUN:   < %t/Use.legacy.sil > %t/Use.legacy.sorted.sil
// RUN: %{python} %S/Inputs/sil_sort_external_entities.py M \
// RUN:   < %t/Use.ondemand.sil > %t/Use.ondemand.sorted.sil
// RUN: diff %t/Use.legacy.sorted.sil %t/Use.ondemand.sorted.sil
// RUN: %FileCheck --check-prefix=USE %s < %t/Use.ondemand.sil

// RUN: %target-swift-frontend -c -parse-as-library -module-name M \
// RUN:   -primary-file %t/Globals.swift -primary-file %t/Use.swift \
// RUN:   -o %t/Globals.legacy.o -o %t/Use.legacy.o
// RUN: %target-swift-frontend -c -parse-as-library -module-name M \
// RUN:   -primary-file %t/Globals.swift -primary-file %t/Use.swift \
// RUN:   -o %t/Globals.ondemand.o -o %t/Use.ondemand.o -sil-verify-all \
// RUN:   -Xllvm -sil-on-demand-emission
// RUN: %llvm-nm --defined-only -j %t/Globals.legacy.o | sort > %t/Globals.legacy.defined
// RUN: %llvm-nm --defined-only -j %t/Globals.ondemand.o | sort > %t/Globals.ondemand.defined
// RUN: diff %t/Globals.legacy.defined %t/Globals.ondemand.defined
// RUN: %llvm-nm --undefined-only -j %t/Globals.legacy.o | sort > %t/Globals.legacy.undefined
// RUN: %llvm-nm --undefined-only -j %t/Globals.ondemand.o | sort > %t/Globals.ondemand.undefined
// RUN: diff %t/Globals.legacy.undefined %t/Globals.ondemand.undefined
// RUN: %llvm-nm --defined-only -j %t/Use.legacy.o | sort > %t/Use.legacy.defined
// RUN: %llvm-nm --defined-only -j %t/Use.ondemand.o | sort > %t/Use.ondemand.defined
// RUN: diff %t/Use.legacy.defined %t/Use.ondemand.defined
// RUN: %llvm-nm --undefined-only -j %t/Use.legacy.o | sort > %t/Use.legacy.undefined
// RUN: %llvm-nm --undefined-only -j %t/Use.ondemand.o | sort > %t/Use.ondemand.undefined
// RUN: diff %t/Use.legacy.undefined %t/Use.ondemand.undefined

// Patterns: a tuple pattern, a binding with several entries, a wildcard, a
// global under #if, and a function with @_silgen_name reading globals.
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   %t/Patterns.swift -o %t/patterns.legacy.sil
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   %t/Patterns.swift -o %t/patterns.ondemand.sil -sil-verify-all \
// RUN:   -Xllvm -sil-on-demand-emission
// RUN: %{python} %S/Inputs/sil_sort_external_entities.py M \
// RUN:   < %t/patterns.legacy.sil > %t/patterns.legacy.sorted.sil
// RUN: %{python} %S/Inputs/sil_sort_external_entities.py M \
// RUN:   < %t/patterns.ondemand.sil > %t/patterns.ondemand.sorted.sil
// RUN: diff %t/patterns.legacy.sorted.sil %t/patterns.ondemand.sorted.sil
// RUN: %FileCheck --check-prefix=PAT %s < %t/patterns.ondemand.sil
// PAT-DAG: sil_global hidden @$s1M1aSivp : $Int
// PAT-DAG: sil_global hidden @$s1M1bSSvp : $String
// PAT-DAG: sil_global hidden @$s1M1dSaySiGvp : $Array<Int>
// PAT-DAG: sil_global hidden [let] @$s1M1eSdvp : $Double
// PAT-DAG: sil_global hidden @$s1M3relSivp : $Int

// A global's lazy initializer is a function without a SILDeclRef, but its
// closures and local functions are in its closure component, as a function's
// are: the closure group passes see them together. Before, on demand ran them
// on the initializer alone and aborted ("partial_apply callee outside the
// closure group", "function set is not closed under scope edges").
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   %t/Closures.swift -o %t/closures.legacy.sil
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   %t/Closures.swift -o %t/closures.ondemand.sil -sil-verify-all \
// RUN:   -Xllvm -sil-on-demand-emission
// RUN: %{python} %S/Inputs/sil_sort_external_entities.py M \
// RUN:   < %t/closures.legacy.sil > %t/closures.legacy.sorted.sil
// RUN: %{python} %S/Inputs/sil_sort_external_entities.py M \
// RUN:   < %t/closures.ondemand.sil > %t/closures.ondemand.sorted.sil
// RUN: diff %t/closures.legacy.sorted.sil %t/closures.ondemand.sorted.sil
// And their diagnostics: an exclusivity conflict inside an initializer.
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   %t/Conflict.swift -o /dev/null -verify
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   %t/Conflict.swift -o /dev/null -verify -Xllvm -sil-on-demand-emission

// Single-root lowering (the user's decision, Phase 6.6): a global the root
// reads stays a declaration; no sil_global, once-token, or initializer.
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   %t/Globals.swift %t/Use.swift -o %t/root.sil -sil-verify-all \
// RUN:   -Xllvm -sil-on-demand-emission -Xllvm -sil-on-demand-root=describe
// RUN: %FileCheck --check-prefix=ROOT %s < %t/root.sil
// ROOT-NOT: sil_global
// ROOT: sil hidden @$s1M8describeSSyF :
// ROOT-NOT: sil_global
// ROOT-DAG: sil hidden_external [global_init] @$s1M7counterSivau :
// ROOT-DAG: sil hidden_external [global_init] @$s1M5namesSaySSGvau :

// CHECK-DAG: sil_global private @$s1M7counter_Wz : $Builtin.Word
// CHECK-DAG: sil_global hidden @$s1M7counterSivp : $Int = {
// CHECK-DAG: sil_global hidden [let] @$s1M5namesSaySSGvp : $Array<String>
// CHECK-DAG: sil private [global_init_once_fn] @$s1M5names_WZ : $@convention(c) (Builtin.RawPointer) -> () {
// CHECK-DAG: sil hidden [global_init] @$s1M5namesSaySSGvau : $@convention(thin) () -> Builtin.RawPointer {
// CHECK-DAG: sil hidden [global_init] @$s1M8observedSivau : $@convention(thin) () -> Builtin.RawPointer {
// CHECK-DAG: sil private @$s1M8observedSivw : $@convention(thin) (Int) -> () {
// CHECK-DAG: sil hidden @$s1M8observedSivs : $@convention(thin) (Int) -> () {
// CHECK-DAG: sil hidden [global_init] @$s1M9mainCountSivau : $@convention(thin) () -> Builtin.RawPointer {
// CHECK-DAG: sil private [global_init] @$s1M6hidden{{.*}}vau : $@convention(thin) () -> Builtin.RawPointer {
// The accessor of a global in another primary is a declaration in Use.swift:
// USE: sil hidden_external [global_init] @$s1M7counterSivau : $@convention(thin) () -> Builtin.RawPointer

//--- Globals.swift
var counter = 0
let names = ["a", "b", "c"]
let answer = 42
let pair = (1, "one")
struct Box { var v: Int }
var box = Box(v: 3)
var computed: Int { counter * 2 }
var observed = 0 { willSet { print("will", newValue) } }
@MainActor var mainCount = 0
private var hidden = [5]
func bump() -> Int { counter += 1; return counter + computed + hidden[0] }
@MainActor func bumpMain() -> Int { mainCount += 1; return mainCount }

//--- Use.swift
func describe() -> String {
  counter += 1
  observed = counter
  return "\(names.count) \(answer) \(pair.1) \(box.v)"
}

//--- Closures.swift
class Ref {}
let h: () -> Int = if var v = Optional(1) { { v += 1; return v } } else { { 0 } }
let w: Int = if var v = Optional(3) { { v *= 2; return v }() } else { 0 }
let weakly: Int = if var r = Optional(Ref()) { { [weak r] in r == nil ? 0 : 1 }() } else { 0 }
struct T {
  static let k: Int = {
    var x = 0
    func inner() { x += 1 }
    inner()
    return x
  }()
}
func readClosures() -> Int { h() + w + weakly + T.k }

//--- Conflict.swift
func mutate(_ x: inout Int, _ f: () -> Void) -> Int { f(); return x }
let g: Int = if var v = Optional(1) {
  mutate(&v) { v = 2 } // expected-error {{overlapping accesses to 'v', but modification requires exclusive access; consider copying to a local variable}}
  // expected-note@-1 {{conflicting access is here}}
} else { 0 }

//--- Patterns.swift
var (a, b) = (1, "two")
var c = 3, d = [4]
let (e, _) = (5.0, 6)
#if NEVER_DEFINED
var dbg = 7
#else
var rel = 8
#endif
@_silgen_name("my_global_reader") func silgenReader() -> Int { a + c + rel }
func readAll() -> String { "\(a) \(b) \(c) \(d) \(e) \(silgenReader())" }
