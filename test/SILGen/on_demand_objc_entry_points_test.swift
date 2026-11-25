//===--- on_demand_objc_entry_points_test.swift ---------------------------===//
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

// Phase 6.5: Objective-C entry points (@objc methods, initializers, properties,
// subscripts, @NSManaged, @objc dynamic + @_dynamicReplacement) and classes
// using the Objective-C allocator (NSObject subclasses: -dealloc,
// .cxx_construct, .cxx_destruct, isolated deinit) are emitted on demand with
// SIL and object-symbol parity against the legacy path. Single-root lowering
// keeps emitting only the root's native body.

// REQUIRES: objc_interop
// REQUIRES: concurrency
// RUN: %empty-directory(%t)
// RUN: split-file %s %t

// 1. Whole-module SIL parity against legacy.
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   %t/Classes.swift %t/Ext.swift -o %t/wmo.legacy.sil
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   -sil-verify-all %t/Classes.swift %t/Ext.swift \
// RUN:   -Xllvm -sil-on-demand-emission -o %t/wmo.ondemand.sil
// RUN: %{python} %S/Inputs/sil_sort_external_entities.py M \
// RUN:   < %t/wmo.legacy.sil | sed -E 's/@opened\([0-9]+,/@opened(N,/g' \
// RUN:   > %t/wmo.legacy.sorted.sil
// RUN: %{python} %S/Inputs/sil_sort_external_entities.py M \
// RUN:   < %t/wmo.ondemand.sil | sed -E 's/@opened\([0-9]+,/@opened(N,/g' \
// RUN:   > %t/wmo.ondemand.sorted.sil
// RUN: diff -u %t/wmo.legacy.sorted.sil %t/wmo.ondemand.sorted.sil

// 2. Batch-mode -c object symbol parity across two primaries.
// RUN: %target-swift-frontend -c -parse-as-library -module-name M \
// RUN:   -primary-file %t/Classes.swift -primary-file %t/Ext.swift \
// RUN:   -o %t/cls.leg.o -o %t/ext.leg.o
// RUN: %target-swift-frontend -c -parse-as-library -module-name M \
// RUN:   -sil-verify-all -primary-file %t/Classes.swift \
// RUN:   -primary-file %t/Ext.swift -o %t/cls.od.o -o %t/ext.od.o \
// RUN:   -Xllvm -sil-on-demand-emission
// RUN: %llvm-nm --defined-only -j %t/cls.leg.o | sort > %t/cls.leg.def
// RUN: %llvm-nm --defined-only -j %t/cls.od.o | sort > %t/cls.od.def
// RUN: diff -u %t/cls.leg.def %t/cls.od.def
// RUN: %llvm-nm --undefined-only -j %t/cls.leg.o | sort > %t/cls.leg.undef
// RUN: %llvm-nm --undefined-only -j %t/cls.od.o | sort > %t/cls.od.undef
// RUN: diff -u %t/cls.leg.undef %t/cls.od.undef
// RUN: %llvm-nm --defined-only -j %t/ext.leg.o | sort > %t/ext.leg.def
// RUN: %llvm-nm --defined-only -j %t/ext.od.o | sort > %t/ext.od.def
// RUN: diff -u %t/ext.leg.def %t/ext.od.def
// RUN: %llvm-nm --undefined-only -j %t/ext.leg.o | sort > %t/ext.leg.undef
// RUN: %llvm-nm --undefined-only -j %t/ext.od.o | sort > %t/ext.od.undef
// RUN: diff -u %t/ext.leg.undef %t/ext.od.undef

// 3. Single-root lowering on an @objc method under lazy type checking emits
// only the native body (no @objc thunk, and unrelated type errors ignored).
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name SR \
// RUN:   -enable-library-evolution -experimental-lazy-typecheck \
// RUN:   -sil-verify-all -primary-file %t/SingleRoot.swift \
// RUN:   -Xllvm -sil-on-demand-emission -Xllvm -sil-on-demand-root=8 \
// RUN:   -o %t/sr.sil
// RUN: %FileCheck --check-prefix=SR %s < %t/sr.sil

// 4. Lazy-typecheck error gating on an NSObject subclass deinit (usesObjCAllocator).
// RUN: not %target-swift-frontend -emit-sil -parse-as-library -module-name LT \
// RUN:   -enable-library-evolution -experimental-lazy-typecheck \
// RUN:   -sil-verify-all -primary-file %t/LazyError.swift \
// RUN:   -Xllvm -sil-on-demand-emission -o /dev/null

// SR: sil @$s2SR3BoxC4workSiyF :
// SR-NOT: @$s2SR3BoxC4workSiyFTo

//--- Classes.swift
import Foundation

open class Box: NSObject {
  @objc public var label: String = "initial"
  @objc public static var sharedCount: Int = 0
  @objc public dynamic var computed: Int {
    get { label.count }
    set { label = "\(newValue)" }
  }
  @objc public subscript(i: Int) -> Int {
    get { i + computed }
    set { computed = newValue - i }
  }

  public override init() {
    super.init()
  }

  @objc public convenience init(named s: String) {
    self.init()
    self.label = s
  }

  @objc public dynamic func ping(_ x: Int) -> Int {
    x + computed
  }

  deinit {
    Box.sharedCount += 1
  }
}

public class QuietObj: NSObject {
  public var tag: Int = 3
  deinit {}
}

@MainActor
public class IsolatedObj: NSObject {
  public var name: String = "main"
  isolated deinit {
    _ = name
  }
}

public class ManagedModel: NSObject {
  @NSManaged public var title: String
}

public class NativeWithObjC {
  @objc public func greet() -> Int { 7 }
  public init() {}
}

//--- Ext.swift
import Foundation

extension Box {
  @objc public func extra(_ y: Int) -> Int {
    ping(y) + 1
  }

  @_dynamicReplacement(for: ping(_:))
  public func pingReplacement(_ x: Int) -> Int {
    x + 100
  }
}

extension NativeWithObjC {
  @objc public var extProp: Int { 9 }
}

//--- SingleRoot.swift
import Foundation

public class Box: NSObject {
  public func broken() -> Int {
    return "not an int"
  }
  @objc public func work() -> Int {
    var x = 1
    x += 2
    return x
  }
}

//--- LazyError.swift
import Foundation

public func brokenFirst() -> Int {
  return "bad"
}

public class Sub: NSObject {
  public var s: String = "hi"
  deinit {
    _ = s
  }
}
