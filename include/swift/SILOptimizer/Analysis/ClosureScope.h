//===--- ClosureScope.h - Determines closure's defining scope ---*- C++ -*-===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
///
/// Map each non-escaping closure SILFunction to a set of SILFunctions
/// corresponding to its parent scopes.
///
/// The closure graph is specific to non-escaping closures. Unlike
/// CallerAnalysis, it does not reflect the call tree. A closure's scope is a
/// function that directly references the closure. It may directly invoke the
/// closure (as a caller) or may simply pass it off as an argument.
///
/// ClosureFunctionOrder builds the graph from a function list each time it is
/// computed, so the graph reflects functions created by earlier passes and
/// needs no invalidation.
///
/// We do not currently mark SILFunctions as non-escaping. However, only
/// closures that are not assigned to an lvalue and are never passed as escaping
/// closures can use the @inout_aliasable convention. For now, we simply limit
/// the graph to such closures. This covers the set of closures that
/// SILOptimizer must view as non-escaping, which must in turn be a subset of
/// Sema's non-escaping closures.
///
/// NOTE: a non-escaping function can be passed as an escaping function via
/// withoutActuallyEscaping. However, using that API to introduce recursion is
/// disallowed according to exclusivity semantics. That is, non-escaping
/// function types cannot be reentrant (SE-0176). We assume that closure scopes
/// are acyclic. Although the language does not currently
/// enforce non-reentrant, non-escaping closures, the scope graph cannot be
/// cyclic because there's no way to name a non-escaping closure. So, in the
/// long term the acyclic assumption made here is protected by
/// non-reentrant semantics, and in the short-term it's safe because of the
/// language's practical limitations.
///
//===----------------------------------------------------------------------===//

#ifndef SWIFT_SILOPTIMIZER_ANALYSIS_CLOSURESCOPE_H
#define SWIFT_SILOPTIMIZER_ANALYSIS_CLOSURESCOPE_H

#include "swift/Basic/Assertions.h"
#include "swift/SIL/SILFunction.h"
#include "swift/SIL/SILModule.h"

namespace swift {

/// Return true if this function is known to be non-escaping.
///
/// This must only return true if the closure was also deemed non-escaping in
/// Sema. Sema will eventually guarantee non-reentrance.
///
/// This must always return true for any closure with @inout_aliasable parameter
/// conventions, because passes like AccessEnforcementSelection assume that
/// convention only applies to non-escaping closures.
///
/// (Hence, SILGen may only use @inout_aliasable for closures that Sema deems
/// non-escaping.)
///
/// This may conservatively return false for any non-escaping closures that
/// don't happen to use @inout_aliasable.
inline bool isNonEscapingClosure(CanSILFunctionType funcTy) {
  auto isInoutAliasable = [](SILParameterInfo paramInfo) {
    return paramInfo.getConvention()
    == ParameterConvention::Indirect_InoutAliasable;
  };
  return llvm::any_of(funcTy->getParameters(), isInoutAliasable);
}

class ApplySite;

/// The non-escaping closure that \p apply applies or partially applies through
/// an @inout_aliasable parameter, or null. Each such apply is an edge of the
/// closure graph, from the apply's function (a scope of the closure) to the
/// closure.
///
/// A closure usually has its scopes in one function. It can have scopes in
/// unrelated functions too: SILGen emits the body of a @backDeployed function
/// twice, as the function and its fallback, and both copies refer to the same
/// closures; a closure cloned by capture promotion refers to the same nested
/// closures as its original.
SILFunction *getScopedClosure(ApplySite apply);

// Visits functions top-down in closure scope order.
class ClosureFunctionOrder {
  class ClosureDFS;
  friend class ClosureDFS;

  // All functions in this module in top-down order (RPO) following the closure
  // scope graph. Functions that define a closure occur before the closure.
  std::vector<SILFunction *> topDownFunctions;

  // If the closure scope graph has any cycles, record each function at the
  // head of a cycle. This does not include all the functions in the
  // strongly-connected component. This is extremely rare. It is always a local
  // function that refers to itself either directly or indirectly.
  SmallPtrSet<SILFunction *, 4> closureCycleHeads;

public:
  ClosureFunctionOrder() = default;

  /// Compute the order over \p functions only, which must be in module
  /// function-list order. The closure graph is built from \p functions, so it
  /// reflects functions created by earlier passes. A closure group transform
  /// uses this with its group.
  void compute(ArrayRef<SILFunction *> functions);

  ArrayRef<SILFunction *> getTopDownFunctions() const {
    return topDownFunctions;
  }

  bool isHeadOfClosureCycle(SILFunction *function) const {
    return closureCycleHeads.contains(function);
  }

  SWIFT_ASSERT_ONLY_DECL(void dump());

protected:
  ClosureFunctionOrder(const ClosureFunctionOrder &) = delete;
  ClosureFunctionOrder &operator=(const ClosureFunctionOrder &) = delete;
};

} // end namespace swift

#endif
