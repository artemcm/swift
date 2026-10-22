//===--- ClosureGroupSchedule.cpp - Closure groups ------------------------===//
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

#include "swift/SILOptimizer/Utils/ClosureGroupSchedule.h"
#include "swift/SIL/SILFunction.h"
#include "swift/SIL/SILInstruction.h"
#include "swift/SIL/SILModule.h"
#include "swift/SIL/Test.h"
#include "swift/SILOptimizer/Analysis/BasicCalleeAnalysis.h"
#include "swift/SILOptimizer/Analysis/FunctionOrder.h"
#include "swift/SILOptimizer/PassManager/Transforms.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/GraphTraits.h"
#include "llvm/ADT/IntEqClasses.h"
#include "llvm/ADT/SCCIterator.h"
#include "llvm/ADT/STLExtras.h"
#include <utility>
#include <vector>

using namespace swift;

/// An edge between two definitions, as (from, to) indices in bottom-up order.
using IndexEdge = std::pair<unsigned, unsigned>;

namespace {
/// A call graph over the components that union-find builds, which become the
/// closure groups: a node per component, an edge for each call into another
/// component, and a root with an edge to every component. The components of an
/// SCC call each other; they run in leader order. Satisfies the requirements
/// of llvm::scc_iterator.
struct ComponentGraph {
  struct Node {
    llvm::SmallVector<Node *, 4> callees;
  };
  /// One node per component, at its component number, plus the root at the
  /// end.
  std::vector<Node> nodes;

  /// \p componentOf maps each bottomUp index to its component number.
  ComponentGraph(llvm::ArrayRef<IndexEdge> callEdges,
                 llvm::ArrayRef<unsigned> componentOf, unsigned numComponents)
      : nodes(numComponents + 1) {
    // A call inside a component is dropped.
    for (auto [caller, callee] : callEdges) {
      unsigned from = componentOf[caller], to = componentOf[callee];
      if (from != to)
        nodes[from].callees.push_back(&nodes[to]);
    }

    // The root calls the components in their leaders' bottom-up order, which
    // makes the DFS deterministic.
    for (unsigned c = 0; c != numComponents; ++c)
      getRoot()->callees.push_back(&nodes[c]);
  }

  Node *getRoot() { return &nodes.back(); }
};
} // end anonymous namespace

namespace llvm {
/// Lets llvm::scc_iterator walk a ComponentGraph from its root along callees.
template <>
struct GraphTraits<ComponentGraph *> {
  using NodeRef = ComponentGraph::Node *;
  using ChildIteratorType = SmallVectorImpl<NodeRef>::iterator;

  static NodeRef getEntryNode(ComponentGraph *graph) {
    return graph->getRoot();
  }
  static ChildIteratorType child_begin(NodeRef node) {
    return node->callees.begin();
  }
  static ChildIteratorType child_end(NodeRef node) {
    return node->callees.end();
  }
};
} // end namespace llvm

/// If \p ref is a closure link, returns the function it refers to, otherwise
/// returns null. The function must be a definition and a closure
/// (SILFunction::isClosure), and must not be a thunk, so that a shared thunk
/// doesn't link unrelated functions.
static SILFunction *getLinkedClosure(FunctionRefInst *ref) {
  SILFunction *f = ref->getInitiallyReferencedFunction();
  if (!f || !f->isDefinition() || !f->isClosure() || f->isThunk() != IsNotThunk)
    return nullptr;
  return f;
}

/// Scans every definition once. Each closure link (getLinkedClosure) joins its
/// scope and closure in \p components. Returns the call edges that
/// BottomUpFunctionOrder follows, once per caller-callee pair, because
/// components aren't final until the scan ends.
static llvm::SmallVector<IndexEdge, 64>
collectEdges(llvm::ArrayRef<SILFunction *> bottomUp,
             const llvm::DenseMap<SILFunction *, unsigned> &bottomUpIndex,
             BasicCalleeAnalysis *bca, llvm::IntEqClasses &components) {
  llvm::SmallVector<IndexEdge, 64> callEdges;
  // The current caller's callees. A function calls the same callee, or
  // releases the same type, from many instructions.
  llvm::SmallDenseSet<unsigned, 16> callees;
  for (unsigned i = 0, e = bottomUp.size(); i != e; ++i) {
    callees.clear();
    auto join = [&](SILFunction *closure) {
      auto it = bottomUpIndex.find(closure);
      if (it != bottomUpIndex.end())
        components.join(i, it->second);
    };
    for (SILBasicBlock &block : *bottomUp[i]) {
      for (SILInstruction &inst : block) {
        if (auto *ref = dyn_cast<FunctionRefBaseInst>(&inst)) {
          if (auto *fri = dyn_cast<FunctionRefInst>(ref))
            if (SILFunction *closure = getLinkedClosure(fri))
              join(closure);
          continue;
        }
        BottomUpFunctionOrder::visitCallees(
            inst, bca, [&](SILFunction *callee) {
              auto it = bottomUpIndex.find(callee);
              if (it != bottomUpIndex.end() &&
                  callees.insert(it->second).second)
                callEdges.push_back({i, it->second});
            });
      }
    }
  }
  return callEdges;
}

// The constructor runs in four steps:
//   1. Number function definitions in bottom-up order.
//   2. Scan every instruction once, building closure components (scopes
//      with their closures) and recording call edges.
//   3. Contract the call graph to one node per component.
//   4. Order the groups so callees come first, when we can: Walk the SCCs of
//      that graph callees first, emitting each component as a group, so a group
//      comes after the groups it calls. Components in one SCC call each other
//      and have no such order, they go in bottom-up order.
ClosureGroupSchedule::ClosureGroupSchedule(SILModule &module,
                                           BasicCalleeAnalysis *bca) {
  // 1. Declarations have no body to schedule.
  llvm::SmallVector<SILFunction *, 32> bottomUp;
  llvm::DenseMap<SILFunction *, unsigned> bottomUpIndex;
  BottomUpFunctionOrder order(module, bca);
  for (SILFunction *f : order.getFunctions()) {
    if (!f->isDefinition())
      continue;
    bottomUpIndex[f] = bottomUp.size();
    bottomUp.push_back(f);
  }
  unsigned n = bottomUp.size();

  // 2. Union-find (IntEqClasses), compress() numbers components in bottom-up
  // order of their first members.
  llvm::IntEqClasses components(n);
  auto callEdges = collectEdges(bottomUp, bottomUpIndex, bca, components);
  components.compress();
  unsigned numComponents = components.getNumClasses();
  llvm::SmallVector<unsigned, 32> componentOf(n);
  // Each component's members in bottom-up order, so the first is its leader.
  llvm::SmallVector<llvm::SmallVector<unsigned, 4>, 32> componentMembers(
      numComponents);
  for (unsigned i = 0; i != n; ++i) {
    componentOf[i] = components[i];
    componentMembers[componentOf[i]].push_back(i);
  }

  // 3. Contract the call graph to component nodes.
  ComponentGraph graph(callEdges, componentOf, numComponents);

  // 4. scc_iterator emits each SCC after the SCCs it calls. The root reaches
  // every component, its own SCC comes last, so skip it.
  unsigned numScheduled = 0;
  for (auto scc = llvm::scc_begin(&graph); !scc.isAtEnd(); ++scc) {
    const std::vector<ComponentGraph::Node *> &sccNodes = *scc;
    if (sccNodes.front() == graph.getRoot())
      continue;
    // Component numbers are bottom-up order (step 2).
    llvm::SmallVector<unsigned, 8> sccComponents;
    for (ComponentGraph::Node *node : sccNodes)
      sccComponents.push_back(node - graph.nodes.data());
    llvm::sort(sccComponents);
    for (unsigned c : sccComponents) {
      Group &group = groups.emplace_back();
      for (unsigned i : componentMembers[c]) // already bottom-up
        group.push_back(bottomUp[i]);
      numScheduled += group.size();
    }
  }
  assert(numScheduled == n && "a component is unreachable from the root");
  (void)numScheduled;
}

void ClosureGroupSchedule::print(llvm::raw_ostream &os) const {
  for (unsigned i = 0, e = groups.size(); i != e; ++i) {
    os << "group " << i << "\n";
    for (SILFunction *f : groups[i])
      os << "  [" << groups[i].front()->getName() << "] " << f->getName()
         << "\n";
  }
}

namespace swift::test {
// Dumps the module's closure groups in schedule order, each member prefixed
// by its group's leader, its first member, in brackets.
static FunctionTest ClosureGroupScheduleTest(
    "closure_group_schedule", [](auto &function, auto &arguments, auto &test) {
      auto *bca = test.template getAnalysis<BasicCalleeAnalysis>();
      ClosureGroupSchedule schedule(function.getModule(), bca);
      schedule.print(llvm::outs());
    });
} // end namespace swift::test
