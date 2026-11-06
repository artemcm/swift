// Phase 6.3: on demand, the seeder walks a file's top-level declarations with
// their auxiliary declarations (getTopLevelDeclsWithAuxiliaryDecls), as
// SILGenModule::emitSourceFile does, so the extension that a macro attached
// to a type adds is seeded, and its conformance gets its witness table. Before,
// @Observable's Observable conformance had none on demand (D17 for macros).
// And a macro's expansion has a source file of its own: the coordinator asks
// for the outermost one, so the members and accessors that @Observable adds
// keep their bodies instead of becoming declarations (D21).

// REQUIRES: swift_swift_parser
// REQUIRES: observation
// REQUIRES: concurrency

// RUN: %empty-directory(%t)
// RUN: split-file %s %t

// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   -plugin-path %swift-plugin-dir %t/Model.swift %t/Use.swift \
// RUN:   -o %t/wmo.legacy.sil
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   -plugin-path %swift-plugin-dir %t/Model.swift %t/Use.swift \
// RUN:   -o %t/wmo.ondemand.sil -sil-verify-all -Xllvm -sil-on-demand-emission
// RUN: %{python} %S/Inputs/sil_sort_external_entities.py M \
// RUN:   < %t/wmo.legacy.sil > %t/wmo.legacy.sorted.sil
// RUN: %{python} %S/Inputs/sil_sort_external_entities.py M \
// RUN:   < %t/wmo.ondemand.sil > %t/wmo.ondemand.sorted.sil
// RUN: diff %t/wmo.legacy.sorted.sil %t/wmo.ondemand.sorted.sil
// RUN: %FileCheck %s < %t/wmo.ondemand.sil

// RUN: %target-swift-frontend -c -parse-as-library -module-name M \
// RUN:   -plugin-path %swift-plugin-dir \
// RUN:   -primary-file %t/Model.swift -primary-file %t/Use.swift \
// RUN:   -o %t/Model.legacy.o -o %t/Use.legacy.o
// RUN: %target-swift-frontend -c -parse-as-library -module-name M \
// RUN:   -plugin-path %swift-plugin-dir \
// RUN:   -primary-file %t/Model.swift -primary-file %t/Use.swift \
// RUN:   -o %t/Model.ondemand.o -o %t/Use.ondemand.o -sil-verify-all \
// RUN:   -Xllvm -sil-on-demand-emission
// RUN: %llvm-nm --defined-only -j %t/Model.legacy.o | sort > %t/Model.legacy.defined
// RUN: %llvm-nm --defined-only -j %t/Model.ondemand.o | sort > %t/Model.ondemand.defined
// RUN: diff %t/Model.legacy.defined %t/Model.ondemand.defined

// CHECK: sil_witness_table hidden Model: Observable module M {

//--- Model.swift
import Observation
@available(macOS 14, iOS 17, tvOS 17, watchOS 10, *)
@Observable final class Model { var x = 0 }

//--- Use.swift
import Observation
@available(macOS 14, iOS 17, tvOS 17, watchOS 10, *)
func use(_ m: some Observable) -> Int { 1 }
@available(macOS 14, iOS 17, tvOS 17, watchOS 10, *)
func call() -> Int { use(Model()) }
