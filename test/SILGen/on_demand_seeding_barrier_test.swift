//===--- on_demand_seeding_barrier_test.swift -----------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

// D25: no pass pipeline may run while OnDemandSeeder is still seeding
// declarations. Otherwise an auxiliary function canonicalized upfront (such as
// a default-argument generator) devirtualizes against a partial class
// hierarchy that lacks subclasses declared later in the file.

// REQUIRES: executable_test
// REQUIRES: asserts
// RUN: %empty-directory(%t)
// RUN: split-file %s %t

// 1. SIL parity: g's default-argument generator and h() both retain dynamic
// class_method dispatch on Base.f because Derived overrides it below.
// RUN: %target-swift-frontend -emit-sil -module-name M %t/main.swift \
// RUN:   -o %t/legacy.sil
// RUN: %target-swift-frontend -emit-sil -module-name M %t/main.swift \
// RUN:   -sil-verify-all -Xllvm -sil-on-demand-emission -o %t/ondemand.sil
// RUN: %FileCheck --check-prefix=SIL %s < %t/ondemand.sil
// RUN: %{python} %S/Inputs/sil_sort_external_entities.py M \
// RUN:   < %t/legacy.sil > %t/legacy.sorted.sil
// RUN: %{python} %S/Inputs/sil_sort_external_entities.py M \
// RUN:   < %t/ondemand.sil > %t/ondemand.sorted.sil
// RUN: diff -u %t/legacy.sorted.sil %t/ondemand.sorted.sil

// 2. Executable parity: built on demand, both g() and h() dispatch to Derived.f
// and print 2.
// RUN: %target-build-swift -module-name M %t/main.swift \
// RUN:   -Xfrontend -sil-verify-all -Xllvm -sil-on-demand-emission -o %t/prog
// RUN: %target-codesign %t/prog
// RUN: %target-run %t/prog | %FileCheck --check-prefix=OUT %s

// 3. Request trace: default-argument generators, @_cdecl thunks, and
// @backDeployed variants emit their raw bodies while seeding, and run no
// pipeline request until [seeding complete].
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name Aux \
// RUN:   %t/Aux.swift -o /dev/null -sil-verify-all \
// RUN:   -Xllvm -sil-on-demand-emission -Xllvm -debug-only=silgen-requests \
// RUN:   2> %t/trace.txt
// RUN: %FileCheck --check-prefix=TRACE %s < %t/trace.txt

// SIL-LABEL: sil hidden @$s1M1gyS2iFfA_ :
// SIL: class_method {{.*}}, #Base.f :
// SIL-LABEL: sil hidden @$s1M1hSiyF :
// SIL: class_method {{.*}}, #Base.f :

// OUT: 2
// OUT-NEXT: 2

// TRACE: -> ArgumentGeneratorsRequest: withDefault(_:)
// TRACE-NOT: CleanedSILFunctionRequest
// TRACE-NOT: DiagnosedSILFunctionRequest
// TRACE-NOT: CanonicalSILFunctionRequest
// TRACE-NOT: CanonicalSynthesizedFunctionRequest
// TRACE: [seeding complete]
// TRACE: -> CanonicalSILFunctionRequest: #withDefault!defaultarg.0
// TRACE: -> CanonicalSILFunctionRequest: #cEntry!foreign
// TRACE: [component] $s3Aux7backDepyS2iFTwB:
// TRACE: [component] $s3Aux7backDepyS2iFTwb:

//--- main.swift
private class Base {
  func f() -> Int { 1 }
}

func g(_ x: Int = make().f()) -> Int { x }

private class Derived: Base {
  override func f() -> Int { 2 }
}

private func make() -> Base { Derived() }

func h() -> Int { make().f() }

print(g())
print(h())

//--- Aux.swift
public func withDefault(_ x: Int = 42) -> Int { x }

@_cdecl("aux_c_entry")
public func cEntry(_ x: Int) -> Int { x + 1 }

@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
@backDeployed(before: macOS 99.0, iOS 99.0, watchOS 99.0, tvOS 99.0)
public func backDep(_ x: Int) -> Int { x + 2 }
