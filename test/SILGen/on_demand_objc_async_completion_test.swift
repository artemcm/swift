//===--- on_demand_objc_async_completion_test.swift -----------------------===//
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

// D27: Foreign async completion-handler block implementation thunks built by
// SILGenModule::getOrCreateForeignAsyncCompletionHandlerImplFunction have no
// SILDeclRef and must be canonicalized via canonicalizeSynthesizedOnDemand so
// AddressLowering runs on them before module verification.

// REQUIRES: objc_interop
// REQUIRES: concurrency
// RUN: %empty-directory(%t)
// RUN: split-file %s %t

// 1. Default async ObjC bridging: WMO sorted SIL diff against legacy.
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   -import-objc-header %t/async_api.h %t/Call.swift %t/Other.swift \
// RUN:   -o %t/wmo.legacy.sil
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   -sil-verify-all -import-objc-header %t/async_api.h \
// RUN:   %t/Call.swift %t/Other.swift -Xllvm -sil-on-demand-emission \
// RUN:   -o %t/wmo.ondemand.sil
// RUN: %{python} %S/Inputs/sil_sort_external_entities.py M \
// RUN:   < %t/wmo.legacy.sil | sed -E 's/@opened\([0-9]+,/@opened(N,/g' \
// RUN:   > %t/wmo.legacy.sorted.sil
// RUN: %{python} %S/Inputs/sil_sort_external_entities.py M \
// RUN:   < %t/wmo.ondemand.sil | sed -E 's/@opened\([0-9]+,/@opened(N,/g' \
// RUN:   > %t/wmo.ondemand.sorted.sil
// RUN: diff -u %t/wmo.legacy.sorted.sil %t/wmo.ondemand.sorted.sil

// 2. Checked async ObjC bridging (-swift-version 6).
// RUN: %target-swift-frontend -swift-version 6 -emit-sil -parse-as-library \
// RUN:   -module-name M -import-objc-header %t/async_api.h \
// RUN:   %t/Call.swift %t/Other.swift -o %t/chk.legacy.sil
// RUN: %target-swift-frontend -swift-version 6 -emit-sil -parse-as-library \
// RUN:   -module-name M -sil-verify-all -import-objc-header %t/async_api.h \
// RUN:   %t/Call.swift %t/Other.swift -Xllvm -sil-on-demand-emission \
// RUN:   -o %t/chk.ondemand.sil
// RUN: %{python} %S/Inputs/sil_sort_external_entities.py M \
// RUN:   < %t/chk.legacy.sil | sed -E 's/@opened\([0-9]+,/@opened(N,/g' \
// RUN:   > %t/chk.legacy.sorted.sil
// RUN: %{python} %S/Inputs/sil_sort_external_entities.py M \
// RUN:   < %t/chk.ondemand.sil | sed -E 's/@opened\([0-9]+,/@opened(N,/g' \
// RUN:   > %t/chk.ondemand.sorted.sil
// RUN: diff -u %t/chk.legacy.sorted.sil %t/chk.ondemand.sorted.sil

// 3. Batch-mode -c object symbol parity.
// RUN: %target-swift-frontend -c -parse-as-library -module-name M \
// RUN:   -import-objc-header %t/async_api.h \
// RUN:   -primary-file %t/Call.swift -primary-file %t/Other.swift \
// RUN:   -o %t/call.leg.o -o %t/other.leg.o
// RUN: %target-swift-frontend -c -parse-as-library -module-name M \
// RUN:   -sil-verify-all -import-objc-header %t/async_api.h \
// RUN:   -primary-file %t/Call.swift -primary-file %t/Other.swift \
// RUN:   -o %t/call.od.o -o %t/other.od.o -Xllvm -sil-on-demand-emission
// RUN: %llvm-nm --defined-only -j %t/call.leg.o | sort > %t/call.leg.def
// RUN: %llvm-nm --defined-only -j %t/call.od.o | sort > %t/call.od.def
// RUN: diff -u %t/call.leg.def %t/call.od.def
// RUN: %llvm-nm --undefined-only -j %t/call.leg.o | sort > %t/call.leg.undef
// RUN: %llvm-nm --undefined-only -j %t/call.od.o | sort > %t/call.od.undef
// RUN: diff -u %t/call.leg.undef %t/call.od.undef

//--- async_api.h
@import Foundation;

NS_ASSUME_NONNULL_BEGIN
@interface AsyncFetcher : NSObject
- (void)fetchCountWithCompletion:(void (^)(NSInteger))completion;
- (void)fetchObjectWithCompletion:(void (^)(NSObject * _Nullable, NSError * _Nullable))completion;
@end
NS_ASSUME_NONNULL_END

//--- Call.swift
import Foundation

public class SwiftAsyncService: NSObject {
  @objc public func makeAny() async -> Any {
    return "bridged_any"
  }
}

public func runFetch(_ f: AsyncFetcher) async throws -> (Int, NSObject) {
  let n = await f.fetchCount()
  let obj = try await f.fetchObject()
  return (n, obj)
}

//--- Other.swift
import Foundation

public func otherHelper() -> Int { 42 }
