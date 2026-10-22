//===--- ClosureGroupSchedule.h - Closure groups ----------------*- C++ -*-===//
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
/// Closure groups: the sets of functions that a SILClosureGroupTransform
/// (Transforms.h) runs on.
///
/// AccessEnforcementSelection and DiagnoseStaticExclusivity must see a function
/// together with the non-escaping closures it captures into, at the same
/// pipeline position. The closure graph has an edge from a function to each
/// closure it applies or partially applies through an @inout_aliasable
/// parameter (getScopedClosure in ClosureScope.h); its connected components
/// are the closure components.
///
/// The scheduling graph has the call edges that BottomUpFunctionOrder follows,
/// plus every closure graph edge in both directions. Its SCCs are the closure
/// groups. Each is a union of closure components, and never splits an SCC of
/// the call graph. Groups are returned callees-first, so function passes
/// scheduled with them still see their callees first. Inside a group, members
/// keep the relative order of the module's bottom-up function order.
///
//===----------------------------------------------------------------------===//

#ifndef SWIFT_SILOPTIMIZER_UTILS_CLOSUREGROUPSCHEDULE_H
#define SWIFT_SILOPTIMIZER_UTILS_CLOSUREGROUPSCHEDULE_H

#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/Support/raw_ostream.h"

namespace swift {

class BasicCalleeAnalysis;
class SILFunction;
class SILModule;

class ClosureGroupSchedule {
public:
  /// The members of one group, in bottom-up order.
  using Group = llvm::SmallVector<SILFunction *, 4>;

private:
  /// Function definitions in the module's bottom-up order.
  llvm::SmallVector<SILFunction *, 32> bottomUp;
  llvm::DenseMap<SILFunction *, unsigned> bottomUpIndex;

  /// The closure component representative of each function.
  llvm::SmallVector<unsigned, 32> componentOf;

  llvm::SmallVector<Group, 16> groups;

public:
  ClosureGroupSchedule(SILModule &module, BasicCalleeAnalysis *bca);

  /// Groups in schedule order: every call-graph callee of a group that is in
  /// another group is in an earlier group.
  llvm::ArrayRef<Group> getGroups() const { return groups; }

  void print(llvm::raw_ostream &os) const;
};

} // end namespace swift

#endif
