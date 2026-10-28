//===--- ClosureGroupPassContext.swift ------------------------------------===//
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

import SIL
import OptimizerBridging

/// The context which is passed to a `ClosureGroupPass`'s run-function.
///
/// A closure group pass runs once per closure group, callees first (see `ClosureGroupSchedule.h`).
/// A group holds the closures that each of its functions forms, so a pass that follows a function's
/// closures stays inside the group. The context provides the group's functions instead of the
/// module's. Like a `ModulePass`, the pass modifies a function only through `transform(function:)`,
/// which accepts only a function in the group.
struct ClosureGroupPassContext : Context {
  let _bridged: BridgedContext

  struct FunctionArray : BridgedRandomAccessCollection {
    fileprivate let bridgedCtxt: BridgedPassContext

    var startIndex: Int { return 0 }
    var endIndex: Int { return bridgedCtxt.getClosureGroupSize() }

    subscript(_ index: Int) -> Function {
      assert(index >= startIndex && index < endIndex)
      return bridgedCtxt.getClosureGroupMember(index).function
    }
  }

  /// The group's definitions when the pass started, in module order.
  var group: FunctionArray { FunctionArray(bridgedCtxt: bridgedPassContext) }

  /// True if `function` is in the group, including a function created since the pass started.
  func isInGroup(_ function: Function) -> Bool {
    bridgedPassContext.isInClosureGroup(function.bridged)
  }

  /// Run a closure with a `PassContext` for a function in the group, which allows to modify that
  /// function.
  ///
  /// Only a single `transform` can be alive at the same time, i.e. it's not allowed to nest
  /// calls to `transform`.
  func transform(function: Function, _ runOnFunction: (FunctionPassContext) -> ()) {
    precondition(isInGroup(function), "transformed function is outside the closure group")
    let nestedBridgedContext = bridgedPassContext.initializeNestedPassContext(function.bridged)
    let nestedContext = FunctionPassContext(_bridged: nestedBridgedContext)
    runOnFunction(nestedContext)
    bridgedPassContext.deinitializedNestedPassContext()
  }

  /// Erase a function in the group.
  func erase(function: Function) {
    bridgedPassContext.eraseFunction(function.bridged)
  }
}
