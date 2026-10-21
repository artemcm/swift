//===--- CaptureSCCSchedule.h - Capture SCCs --------------------*- C++ -*-===//
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
///
/// \file
///
/// Capture SCCs: the sets of functions that a SILCaptureSCCTransform
/// (Transforms.h) runs on.
///
/// Some passes must see a function together with the closures and local
/// functions that it forms or passes captures to, all at the same pipeline
/// position: capture promotion, access enforcement selection, box-to-stack
/// promotion, static exclusivity diagnostics. They only ever look across a
/// capture link.
///
/// There is a capture link between function definitions F and G if F
/// references G with a function_ref (or dynamic_function_ref), G is not a
/// thunk, and one of:
///
///   R1: G has a parameter that receives a capture by reference: a box, or an
///       @inout_aliasable address.
///   R2: F forms a closure from G with partial_apply.
///   R3: G's DeclContext is a local context (a closure or a declaration inside
///       a function body).
///
/// A capture component is a connected component of capture links.
///
/// The scheduling graph has the call edges that BottomUpFunctionOrder follows,
/// plus every capture link in both directions. Its SCCs are the capture SCCs.
/// Each is a union of capture components, and never splits an SCC of the call
/// graph. "SCC" alone below means a capture SCC. SCCs are returned callees-first,
/// so function passes still see their callees first. Inside an SCC, members
/// keep the relative order of the module's bottom-up function order.
///
//===----------------------------------------------------------------------===//

#ifndef SWIFT_SILOPTIMIZER_UTILS_CAPTURESCCSCHEDULE_H
#define SWIFT_SILOPTIMIZER_UTILS_CAPTURESCCSCHEDULE_H

#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/IntEqClasses.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/Support/raw_ostream.h"

namespace swift {

class BasicCalleeAnalysis;
class FunctionRefBaseInst;
class SILFunction;
class SILModule;

class CaptureSCCSchedule {
public:
  /// The members of one SCC, in bottom-up order.
  using SCC = llvm::SmallVector<SILFunction *, 4>;

private:
  /// Function definitions in the module's bottom-up order.
  llvm::SmallVector<SILFunction *, 32> bottomUp;
  llvm::DenseMap<SILFunction *, unsigned> bottomUpIndex;

  /// Classes of bottomUp indices: capture components, then SCCs. A class's
  /// leader is its earliest bottom-up member.
  llvm::IntEqClasses groups;

  /// The capture component representative of each function.
  llvm::SmallVector<unsigned, 32> componentOf;

  llvm::SmallVector<SCC, 16> sccs;

public:
  CaptureSCCSchedule(SILModule &module, BasicCalleeAnalysis *bca);

  /// SCCs in schedule order: every call-graph callee of an SCC that is in
  /// another SCC is in an earlier SCC.
  llvm::ArrayRef<SCC> getSCCs() const { return sccs; }

  void print(llvm::raw_ostream &os) const;

private:
  /// True if \p ref, in \p caller, links the caller and the referenced
  /// function with a capture link (rules R1 to R3).
  static bool isCaptureLink(SILFunction *caller, FunctionRefBaseInst *ref);

  void computeCaptureComponents();
  void computeSCCs(BasicCalleeAnalysis *bca);
};

} // end namespace swift

#endif
