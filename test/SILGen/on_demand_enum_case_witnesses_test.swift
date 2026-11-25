// Phase 6.3: on demand, a function that every referencing unit emits for
// itself (isEmittedOnDemand) has its body before anything that references it
// is linked, as on the legacy path, where every body exists before any pass
// runs. Two kinds reach it: an enum case's constructor, which the witness
// thunk of a requirement that the case satisfies calls (G-41), and a
// Clang-synthesized accessor, such as an imported C enum's rawValue getter.
// Before, OnDemandSILLinker asserted on the bodiless shared declaration
// (D18). Every unit that references such a function emits it, whichever file
// declares it, and the cross-primary stripping keeps it and the thunks, which
// belong to the conformance's file: an enum case's constructor, and the
// `_read` accessor that a `@_borrowed` requirement gives a stored property
// (forced static dispatch), from a struct in another file.

// RUN: %empty-directory(%t)
// RUN: split-file %s %t

// Whole module.
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   -I %t/inc %t/Make.swift %t/Remote.swift %t/Conform.swift %t/C.swift %t/Raw.swift \
// RUN:   -o %t/wmo.legacy.sil
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   -I %t/inc %t/Make.swift %t/Remote.swift %t/Conform.swift %t/C.swift %t/Raw.swift \
// RUN:   -o %t/wmo.ondemand.sil -sil-verify-all -Xllvm -sil-on-demand-emission
// RUN: %{python} %S/Inputs/sil_sort_external_entities.py M \
// RUN:   < %t/wmo.legacy.sil > %t/wmo.legacy.sorted.sil
// RUN: %{python} %S/Inputs/sil_sort_external_entities.py M \
// RUN:   < %t/wmo.ondemand.sil > %t/wmo.ondemand.sorted.sil
// RUN: diff %t/wmo.legacy.sorted.sil %t/wmo.ondemand.sorted.sil
// RUN: %FileCheck %s < %t/wmo.ondemand.sil

// Batch mode, -emit-sil and -c: the enum in Remote.swift, its conformance in
// Conform.swift.
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   -I %t/inc -primary-file %t/Make.swift -primary-file %t/Remote.swift \
// RUN:   -primary-file %t/Conform.swift -primary-file %t/C.swift \
// RUN:   -primary-file %t/Raw.swift \
// RUN:   -o %t/Make.legacy.sil -o %t/Remote.legacy.sil \
// RUN:   -o %t/Conform.legacy.sil -o %t/C.legacy.sil -o %t/Raw.legacy.sil
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   -I %t/inc -primary-file %t/Make.swift -primary-file %t/Remote.swift \
// RUN:   -primary-file %t/Conform.swift -primary-file %t/C.swift \
// RUN:   -primary-file %t/Raw.swift \
// RUN:   -o %t/Make.ondemand.sil -o %t/Remote.ondemand.sil \
// RUN:   -o %t/Conform.ondemand.sil -o %t/C.ondemand.sil -o %t/Raw.ondemand.sil \
// RUN:   -sil-verify-all -Xllvm -sil-on-demand-emission
// RUN: %{python} %S/Inputs/sil_sort_external_entities.py M \
// RUN:   < %t/Conform.legacy.sil > %t/Conform.legacy.sorted.sil
// RUN: %{python} %S/Inputs/sil_sort_external_entities.py M \
// RUN:   < %t/Conform.ondemand.sil > %t/Conform.ondemand.sorted.sil
// RUN: diff %t/Conform.legacy.sorted.sil %t/Conform.ondemand.sorted.sil
// RUN: %FileCheck --check-prefix=CONFORM %s < %t/Conform.ondemand.sil
// RUN: %{python} %S/Inputs/sil_sort_external_entities.py M \
// RUN:   < %t/C.legacy.sil > %t/C.legacy.sorted.sil
// RUN: %{python} %S/Inputs/sil_sort_external_entities.py M \
// RUN:   < %t/C.ondemand.sil > %t/C.ondemand.sorted.sil
// RUN: diff %t/C.legacy.sorted.sil %t/C.ondemand.sorted.sil
// RUN: %{python} %S/Inputs/sil_sort_external_entities.py M \
// RUN:   < %t/Raw.legacy.sil > %t/Raw.legacy.sorted.sil
// RUN: %{python} %S/Inputs/sil_sort_external_entities.py M \
// RUN:   < %t/Raw.ondemand.sil > %t/Raw.ondemand.sorted.sil
// RUN: diff %t/Raw.legacy.sorted.sil %t/Raw.ondemand.sorted.sil
// RUN: %FileCheck --check-prefix=RAW %s < %t/Raw.ondemand.sil

// RUN: %target-swift-frontend -c -parse-as-library -module-name M \
// RUN:   -I %t/inc -primary-file %t/Make.swift -primary-file %t/Remote.swift \
// RUN:   -primary-file %t/Conform.swift -primary-file %t/C.swift \
// RUN:   -primary-file %t/Raw.swift \
// RUN:   -o %t/Make.legacy.o -o %t/Remote.legacy.o \
// RUN:   -o %t/Conform.legacy.o -o %t/C.legacy.o -o %t/Raw.legacy.o
// RUN: %target-swift-frontend -c -parse-as-library -module-name M \
// RUN:   -I %t/inc -primary-file %t/Make.swift -primary-file %t/Remote.swift \
// RUN:   -primary-file %t/Conform.swift -primary-file %t/C.swift \
// RUN:   -primary-file %t/Raw.swift \
// RUN:   -o %t/Make.ondemand.o -o %t/Remote.ondemand.o \
// RUN:   -o %t/Conform.ondemand.o -o %t/C.ondemand.o -o %t/Raw.ondemand.o \
// RUN:   -sil-verify-all -Xllvm -sil-on-demand-emission
// RUN: %llvm-nm --defined-only -j %t/Conform.legacy.o | sort > %t/Conform.legacy.defined
// RUN: %llvm-nm --defined-only -j %t/Conform.ondemand.o | sort > %t/Conform.ondemand.defined
// RUN: diff %t/Conform.legacy.defined %t/Conform.ondemand.defined
// RUN: %llvm-nm --undefined-only -j %t/Conform.legacy.o | sort > %t/Conform.legacy.undefined
// RUN: %llvm-nm --undefined-only -j %t/Conform.ondemand.o | sort > %t/Conform.ondemand.undefined
// RUN: diff %t/Conform.legacy.undefined %t/Conform.ondemand.undefined
// RUN: %llvm-nm --defined-only -j %t/C.legacy.o | sort > %t/C.legacy.defined
// RUN: %llvm-nm --defined-only -j %t/C.ondemand.o | sort > %t/C.ondemand.defined
// RUN: diff %t/C.legacy.defined %t/C.ondemand.defined

// The `_read` accessor of a struct in another primary, which Borrow.swift's
// witness thunk calls: a shared definition in Borrow.swift's object.
// RUN: %target-swift-frontend -c -parse-as-library -module-name M \
// RUN:   -primary-file %t/Borrow.swift -primary-file %t/Holder.swift \
// RUN:   -o %t/Borrow.legacy.o -o %t/Holder.legacy.o
// RUN: %target-swift-frontend -c -parse-as-library -module-name M \
// RUN:   -primary-file %t/Borrow.swift -primary-file %t/Holder.swift \
// RUN:   -o %t/Borrow.ondemand.o -o %t/Holder.ondemand.o -sil-verify-all \
// RUN:   -Xllvm -sil-on-demand-emission
// RUN: %llvm-nm --defined-only -j %t/Borrow.legacy.o | sort > %t/Borrow.legacy.defined
// RUN: %llvm-nm --defined-only -j %t/Borrow.ondemand.o | sort > %t/Borrow.ondemand.defined
// RUN: diff %t/Borrow.legacy.defined %t/Borrow.ondemand.defined
// RUN: %llvm-nm --undefined-only -j %t/Borrow.legacy.o | sort > %t/Borrow.legacy.undefined
// RUN: %llvm-nm --undefined-only -j %t/Borrow.ondemand.o | sort > %t/Borrow.ondemand.undefined
// RUN: diff %t/Borrow.legacy.undefined %t/Borrow.ondemand.undefined
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   -primary-file %t/Borrow.swift %t/Holder.swift \
// RUN:   -o %t/Borrow.ondemand.sil -Xllvm -sil-on-demand-emission
// RUN: %FileCheck --check-prefix=BORROW %s < %t/Borrow.ondemand.sil
// BORROW: sil shared @$s1M6HolderV1xSivr : $@yield_once @convention(method) (Holder) -> @yields Int {

// The constructors of the cases that witness requirements, and the thunks:
// CHECK-DAG: sil shared [transparent] @$s1M5LocalO4zeroyA2CmF :
// CHECK-DAG: sil shared [transparent] @$s1M5LocalO3oneyACSicACmF :
// CHECK-DAG: sil private [transparent] [thunk] @$s1M5LocalOAA4MakeA2aDP4zeroxvgZTW :
// CHECK-DAG: sil shared [transparent] @$s1M6RemoteO4zeroyA2CmF :
// The Clang-synthesized getter that CColor.tick reads:
// CHECK-DAG: sil shared @$sSo6CColorV8rawValues5Int32Vvg :
// CONFORM-DAG: sil shared [transparent] @$s1M6RemoteO4zeroyA2CmF :
// CONFORM-DAG: sil shared [transparent] @$s1M6RemoteO3oneyACSicACmF :
// CONFORM-DAG: sil private [transparent] [thunk] @$s1M6RemoteOAA4MakeA2aDP4zeroxvgZTW :
// CONFORM-DAG: sil_witness_table hidden Remote: Make module M {
// RAW: sil shared @$sSo6CShadeV8rawValues5Int32Vvg :

//--- inc/module.modulemap
module CColors { header "colors.h" export * }

//--- inc/colors.h
typedef enum __attribute__((enum_extensibility(open))) CColor : int { CRed, CGreen } CColor;
typedef enum __attribute__((enum_extensibility(open))) CShade : int { CLight, CDark } CShade;

//--- Make.swift
protocol Make { static var zero: Self { get }; static func one(_ x: Int) -> Self }
enum Local: Make { case zero; case one(Int) }
func build<T: Make>(_: T.Type) -> (T, T) { (T.zero, T.one(1)) }

//--- Remote.swift
enum Remote: Equatable { case zero; case one(Int) }

//--- Conform.swift
extension Remote: Make {}

//--- C.swift
import CColors
protocol Ticks { func tick() -> Int }
extension CColor: Ticks { func tick() -> Int { rawValue == 0 ? 0 : 1 } }
func same(_ a: CColor, _ b: CColor) -> Bool { a == b }

//--- Raw.swift
import CColors
// No conformance of the module's references CShade's getter: only this
// function's own pipeline can need its body.
func isLight(_ s: CShade) -> Bool { s.rawValue == 0 }

//--- Borrow.swift
protocol Borrow { @_borrowed var x: Int { get } }
extension Holder: Borrow {}
func read(_ b: some Borrow) -> Int { b.x }

//--- Holder.swift
struct Holder { var x: Int = 0 }
