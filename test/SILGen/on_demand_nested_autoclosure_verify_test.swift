//===--- on_demand_nested_autoclosure_verify_test.swift -------------------===//
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

// D16: Under -O -sil-verify-all, an @autoclosure member of a closure component
// gets its DominanceInfo cached in the outer SILPassManager during the early
// closure-group passes. When the parent function runs OnDemandMandatoryInlining
// first, inlining precondition triggers a nested CanonicalSILFunctionRequest on
// the transparent autoclosure, rewriting its CFG in an inner SILPassManager.
// The outer SILPassManager must invalidate its cached analyses for the callee
// and skip already-canonical members so passes do not run a second time or
// abort DominanceInfo::verify.

// REQUIRES: asserts
// RUN: %empty-directory(%t)

// 1. -O -sil-verify-all exits 0 on demand, in both WMO and primary-file mode.
// RUN: %target-swift-frontend -O -emit-sil -sil-verify-all -parse-as-library \
// RUN:   -module-name M %s -o /dev/null -Xllvm -sil-on-demand-emission
// RUN: %target-swift-frontend -O -emit-sil -sil-verify-all -parse-as-library \
// RUN:   -module-name M -primary-file %s -o /dev/null \
// RUN:   -Xllvm -sil-on-demand-emission

// 2. Pass-count check: NoReturnFolding runs only once on the autoclosure.
// RUN: %target-swift-frontend -O -emit-sil -sil-verify-all -parse-as-library \
// RUN:   -module-name M %s -o /dev/null -Xllvm -sil-on-demand-emission \
// RUN:   -Xllvm -sil-print-pass-name > %t/passes.txt 2>&1
// RUN: %FileCheck %s < %t/passes.txt

// CHECK: NoReturnFolding (noreturn-folding), Function: $s1M7CmdInfoV11completableSayAA3ArgVGvgSbAFXEfU_SbyKXEfu_SbyKXEfu0_
// CHECK-NOT: NoReturnFolding (noreturn-folding), Function: $s1M7CmdInfoV11completableSayAA3ArgVGvgSbAFXEfU_SbyKXEfu_SbyKXEfu0_

public struct Arg {
  public var show: Bool
  public var tag: String?
  public var names: [String]?
}

public struct CmdInfo {
  public var items: [Arg]?

  public var completable: [Arg] {
    (items ?? []).filter { arg in
      arg.show && (arg.tag != nil || arg.names?.isEmpty == false)
    }
  }
}
