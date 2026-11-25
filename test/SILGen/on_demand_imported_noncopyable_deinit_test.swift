//===--- on_demand_imported_noncopyable_deinit_test.swift -----------------===//
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

// D26: An imported C ~Copyable struct with a custom destroy function emits its
// destructor via SILGenModule::visitImportedNontrivialNoncopyableType. On
// demand, that destructor must be canonicalized even though its DeclContext is
// a ClangModuleUnit (outside filesToEmit).

// RUN: %empty-directory(%t)
// RUN: split-file %s %t

// WMO and batch-mode SIL + object compilation with -sil-verify-all.
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   -I %t %t/Use.swift %t/Other.swift -o %t/wmo.legacy.sil
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   -sil-verify-all -I %t %t/Use.swift %t/Other.swift \
// RUN:   -Xllvm -sil-on-demand-emission -o %t/wmo.ondemand.sil
// RUN: %{python} %S/Inputs/sil_sort_external_entities.py M \
// RUN:   < %t/wmo.legacy.sil > %t/wmo.legacy.sorted.sil
// RUN: %{python} %S/Inputs/sil_sort_external_entities.py M \
// RUN:   < %t/wmo.ondemand.sil > %t/wmo.ondemand.sorted.sil
// RUN: diff -u %t/wmo.legacy.sorted.sil %t/wmo.ondemand.sorted.sil

// RUN: %target-swift-frontend -c -parse-as-library -module-name M \
// RUN:   -I %t -primary-file %t/Use.swift -primary-file %t/Other.swift \
// RUN:   -o %t/use.leg.o -o %t/other.leg.o
// RUN: %target-swift-frontend -c -parse-as-library -module-name M \
// RUN:   -I %t -primary-file %t/Use.swift -primary-file %t/Other.swift \
// RUN:   -o %t/use.od.o -o %t/other.od.o -sil-verify-all \
// RUN:   -Xllvm -sil-on-demand-emission
// RUN: %llvm-nm --defined-only -j %t/use.leg.o | sort > %t/use.leg.def
// RUN: %llvm-nm --defined-only -j %t/use.od.o | sort > %t/use.od.def
// RUN: diff -u %t/use.leg.def %t/use.od.def
// RUN: %llvm-nm --undefined-only -j %t/use.leg.o | sort > %t/use.leg.undef
// RUN: %llvm-nm --undefined-only -j %t/use.od.o | sort > %t/use.od.undef
// RUN: diff -u %t/use.leg.undef %t/use.od.undef

//--- module.modulemap
module CNonCopyable {
  header "c_noncopyable.h"
  export *
}

//--- c_noncopyable.h
struct __attribute__((swift_attr("~Copyable")))
__attribute__((swift_attr("destroy:destroyCBox"))) CBox {
  int value;
};

static inline void destroyCBox(struct CBox box) {}

//--- Use.swift
import CNonCopyable

public func consumeBox() -> Int32 {
  let b = CBox(value: 7)
  return b.value
}

//--- Other.swift
public func helper() -> Int { 1 }
