//===--- on_demand_objc_implementation_test.swift -------------------------===//
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

// D24: @_objcImplementation / @objcImplementation extensions (both main-class
// and category implementations, stored properties, initializers, methods, and
// synthesized destructors parented on the imported Clang ClassDecl) are
// emitted on demand with SIL and batch-mode object-symbol parity.

// REQUIRES: objc_interop
// RUN: %empty-directory(%t)
// RUN: split-file %s %t

// 1. Whole-module SIL parity against legacy.
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   -import-objc-header %t/CWidget.h %t/Impl.swift %t/Client.swift \
// RUN:   -o %t/wmo.legacy.sil
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   -sil-verify-all -import-objc-header %t/CWidget.h \
// RUN:   %t/Impl.swift %t/Client.swift -Xllvm -sil-on-demand-emission \
// RUN:   -o %t/wmo.ondemand.sil
// RUN: %{python} %S/Inputs/sil_sort_external_entities.py M \
// RUN:   < %t/wmo.legacy.sil > %t/wmo.legacy.sorted.sil
// RUN: %{python} %S/Inputs/sil_sort_external_entities.py M \
// RUN:   < %t/wmo.ondemand.sil > %t/wmo.ondemand.sorted.sil
// RUN: diff -u %t/wmo.legacy.sorted.sil %t/wmo.ondemand.sorted.sil

// 2. Batch-mode -c IRGen & symbol parity on both Impl.o and Client.o.
// RUN: %target-swift-frontend -c -parse-as-library -module-name M \
// RUN:   -import-objc-header %t/CWidget.h \
// RUN:   -primary-file %t/Impl.swift -primary-file %t/Client.swift \
// RUN:   -o %t/impl.leg.o -o %t/client.leg.o
// RUN: %target-swift-frontend -c -parse-as-library -module-name M \
// RUN:   -sil-verify-all -import-objc-header %t/CWidget.h \
// RUN:   -primary-file %t/Impl.swift -primary-file %t/Client.swift \
// RUN:   -o %t/impl.od.o -o %t/client.od.o -Xllvm -sil-on-demand-emission
// RUN: %llvm-nm --defined-only -j %t/impl.leg.o | sort > %t/impl.leg.def
// RUN: %llvm-nm --defined-only -j %t/impl.od.o | sort > %t/impl.od.def
// RUN: diff -u %t/impl.leg.def %t/impl.od.def
// RUN: %llvm-nm --undefined-only -j %t/impl.leg.o | sort > %t/impl.leg.undef
// RUN: %llvm-nm --undefined-only -j %t/impl.od.o | sort > %t/impl.od.undef
// RUN: diff -u %t/impl.leg.undef %t/impl.od.undef
// RUN: %llvm-nm --defined-only -j %t/client.leg.o | sort > %t/client.leg.def
// RUN: %llvm-nm --defined-only -j %t/client.od.o | sort > %t/client.od.def
// RUN: diff -u %t/client.leg.def %t/client.od.def

//--- CWidget.h
@import Foundation;

NS_ASSUME_NONNULL_BEGIN
@interface CWidget : NSObject
@property (nonatomic, copy) NSString *name;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithName:(NSString *)name NS_DESIGNATED_INITIALIZER;
- (NSInteger)compute:(NSInteger)x;
@end

@interface CWidget (Extras)
- (NSInteger)bonus;
@end
NS_ASSUME_NONNULL_END

//--- Impl.swift
import Foundation

@objc @implementation extension CWidget {
  public var name: String = "default"
  final var factor: Int = 3

  @objc(initWithName:)
  public init(name: String) {
    self.name = name
    super.init()
  }

  public func compute(_ x: Int) -> Int {
    x * factor + name.count
  }
}

@objc(Extras) @implementation extension CWidget {
  public func bonus() -> Int {
    compute(2) + 5
  }
}

//--- Client.swift
import Foundation

public func makeAndRun() -> Int {
  let w = CWidget(name: "abc")
  return w.bonus()
}
