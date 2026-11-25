//===--- on_demand_objc_executable_test.swift -----------------------------===//
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

// End-to-end executable parity for Phase 6.5: NSObject subclasses (.cxx_construct,
// .cxx_destruct, -dealloc), @objc protocols, KVC #keyPath, @objc dynamic +
// @_dynamicReplacement, and @objc async completion-handler calls, compiled in
// multi-primary batch mode completely on demand, linked, and executed.

// REQUIRES: executable_test
// REQUIRES: objc_interop
// REQUIRES: concurrency
// REQUIRES: concurrency_runtime
// RUN: %empty-directory(%t)
// RUN: split-file %s %t

// Compile all three primaries on demand in batch mode, link, and run.
// RUN: %target-swift-frontend -c -module-name App \
// RUN:   -import-objc-header %t/Bridge.h \
// RUN:   -primary-file %t/Model.swift \
// RUN:   -primary-file %t/Ext.swift \
// RUN:   -primary-file %t/main.swift \
// RUN:   -o %t/Model.o -o %t/Ext.o -o %t/main.o \
// RUN:   -sil-verify-all -Xllvm -sil-on-demand-emission
// RUN: %target-build-swift %t/Model.o %t/Ext.o %t/main.o -o %t/app
// RUN: %target-codesign %t/app
// RUN: %target-run %t/app | %FileCheck --check-prefix=OUT %s

// OUT: kvc=hello
// OUT-NEXT: proto=15
// OUT-NEXT: dyn=107
// OUT-NEXT: async=21
// OUT-NEXT: deinit=1,ivarDestroyed=1

//--- Bridge.h
@import Foundation;

NS_ASSUME_NONNULL_BEGIN
@protocol AsyncProvider <NSObject>
- (void)computeDouble:(NSInteger)x completion:(void (^)(NSInteger))completion;
@end
NS_ASSUME_NONNULL_END

//--- Model.swift
import Foundation

public final class Tracker {
  public static var ivarDestroyed = 0
  public static var deinitCount = 0
  public init() {}
  deinit { Tracker.ivarDestroyed += 1 }
}

@objc public protocol Scorer {
  @objc func score(_ base: Int) -> Int
}

public class Item: NSObject, Scorer, AsyncProvider {
  @objc public var title: String = "hello"
  public var tracker: Tracker = Tracker()

  @objc public func score(_ base: Int) -> Int {
    base + title.count
  }

  @objc public dynamic func adjust(_ x: Int) -> Int {
    x + 1
  }

  @objc public func computeDouble(_ x: Int, completion: @escaping (Int) -> Void) {
    completion(x * 3)
  }

  deinit {
    Tracker.deinitCount += 1
  }
}

//--- Ext.swift
import Foundation

extension Item {
  @_dynamicReplacement(for: adjust(_:))
  public func adjustReplaced(_ x: Int) -> Int {
    x + 100
  }
}

func callAsync(_ p: any AsyncProvider, _ x: Int) async -> Int {
  await p.computeDouble(x)
}

//--- main.swift
import Foundation

func runScope() async {
  let item = Item()
  let kvc = item.value(forKey: #keyPath(Item.title)) as? String ?? "none"
  print("kvc=\(kvc)")

  let scorer: AnyObject = item
  print("proto=\(scorer.score?(10) ?? -1)")
  print("dyn=\(item.adjust(7))")

  let res = await callAsync(item, 7)
  print("async=\(res)")
}

await runScope()
print("deinit=\(Tracker.deinitCount),ivarDestroyed=\(Tracker.ivarDestroyed)")
