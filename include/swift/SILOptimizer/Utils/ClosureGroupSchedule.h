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
/// Closure groups: the units a SILClosureGroupTransform (Transforms.h) runs on.
///
/// A closure component is a connected component of closure links: a function,
/// the closures and local functions it references, and every other function
/// that references them. A link is a function_ref or dynamic_function_ref to a
/// closure or local function, whatever it captures and however it is used. A
/// closure can have scopes in unrelated functions, e.g. a @backDeployed
/// function and its fallback.
///
/// A closure group is an SCC of the call graph that BottomUpFunctionOrder
/// follows, with each closure component contracted to one node. Groups are
/// ordered callees first; members keep their bottom-up order.
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

  /// For print(): each function's closure component, as the bottomUp index of
  /// its leader.
  llvm::SmallVector<unsigned, 32> componentOf;

  llvm::SmallVector<Group, 16> groups;

public:
  ClosureGroupSchedule(SILModule &module, BasicCalleeAnalysis *bca);

  /// Groups in schedule order: a group's callees in other groups come earlier.
  llvm::ArrayRef<Group> getGroups() const { return groups; }

  void print(llvm::raw_ostream &os) const;
};

} // end namespace swift

#endif
