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
#include "swift/AST/DeclContext.h"
#include "swift/SIL/ApplySite.h"
#include "swift/SIL/SILFunction.h"
#include "swift/SIL/SILInstruction.h"
#include "swift/SIL/SILModule.h"
#include "swift/SIL/Test.h"
#include "swift/SILOptimizer/Analysis/BasicCalleeAnalysis.h"
#include "swift/SILOptimizer/Analysis/ClosureScope.h"
#include "swift/SILOptimizer/Analysis/FunctionOrder.h"
#include "swift/SILOptimizer/PassManager/Transforms.h"
#include "llvm/ADT/GraphTraits.h"
#include "llvm/ADT/IntEqClasses.h"
#include "llvm/ADT/SCCIterator.h"
#include "llvm/ADT/STLExtras.h"
#include <utility>
#include <vector>

using namespace swift;

namespace {
/// A call graph over closure components (ClosureGroupSchedule.h): a node per
/// component, an edge for each call into another component, and a root with
/// an edge to every component.
/// Satisfies the requirements of llvm::scc_iterator.
struct ComponentGraph {
  struct Node {
    llvm::SmallVector<Node *, 4> callees;
  };
  /// One slot per function, at its bottomUp index, plus the root at the end.
  /// A component's node is its leader's node, other nodes are unused.
  std::vector<Node> nodes;

  /// \p componentOf maps each bottomUp index to its component's leader.
  ComponentGraph(llvm::ArrayRef<std::pair<unsigned, unsigned>> callEdges,
                 llvm::ArrayRef<unsigned> componentOf)
      : nodes(componentOf.size() + 1) {
    // A call inside a component is dropped.
    for (auto [caller, callee] : callEdges) {
      unsigned from = componentOf[caller], to = componentOf[callee];
      if (from != to)
        nodes[from].callees.push_back(&nodes[to]);
    }

    // The root calls the leaders in bottom-up order, which makes the DFS
    // deterministic.
    for (unsigned i = 0, e = componentOf.size(); i != e; ++i)
      if (componentOf[i] == i)
        getRoot()->callees.push_back(&nodes[i]);
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

/// The closure that \p ref links to \p scope, or null. It is a definition,
/// other than the scope and not a thunk, that is a closure or local function by
/// one of three markers:
///   - An argument is a closure capture. SILGen marks every kind of capture.
///   - A parameter has a capture convention, @inout_aliasable or a box. This
///     covers hand-written SIL, which needn't mark its captures.
///   - Its declaration is nested in a local context. This covers closures and
///     local functions that capture nothing.
/// Thunks are excluded so that a shared one, such as a reabstraction thunk,
/// doesn't link unrelated functions.
static SILFunction *getLinkedClosure(SILFunction *scope,
                                     FunctionRefBaseInst *ref) {
  SILFunction *f = ref->getInitiallyReferencedFunction();
  if (!f || f == scope || !f->isDefinition() || f->isThunk() != IsNotThunk)
    return nullptr;
  if (llvm::any_of(f->getArguments(), [](SILArgument *arg) {
        return cast<SILFunctionArgument>(arg)->isClosureCapture();
      }))
    return f;
  CanSILFunctionType type = f->getLoweredFunctionType();
  if (isNonEscapingClosure(type) ||
      llvm::any_of(type->getParameters(), [](SILParameterInfo param) {
        return param.getInterfaceType()->is<SILBoxType>();
      }))
    return f;
  // A function's own context is always local (its body), so test the parent.
  if (DeclContext *dc = f->getDeclContext())
    if (DeclContext *parent = dc->getParent())
      if (parent->isLocalContext())
        return f;
  return nullptr;
}

/// Scans every definition once. Each closure link (getLinkedClosure) joins its
/// scope and closure in \p components, and so does each closure edge
/// (getScopedClosure). The edges also cover a thunk with an @inout_aliasable
/// parameter, so a group stays closed under ClosureFunctionOrder's edges. The
/// call edges BottomUpFunctionOrder follows are returned as (caller, callee)
/// bottomUp indices, because the components aren't final until the scan ends.
/// A self-call can't link two components, so it is skipped.
static llvm::SmallVector<std::pair<unsigned, unsigned>, 64>
collectEdges(llvm::ArrayRef<SILFunction *> bottomUp,
             const llvm::DenseMap<SILFunction *, unsigned> &bottomUpIndex,
             BasicCalleeAnalysis *bca, llvm::IntEqClasses &components) {
  llvm::SmallVector<std::pair<unsigned, unsigned>, 64> callEdges;
  for (unsigned i = 0, e = bottomUp.size(); i != e; ++i) {
    auto join = [&](SILFunction *closure) {
      auto it = bottomUpIndex.find(closure);
      if (it != bottomUpIndex.end())
        components.join(i, it->second);
    };
    for (SILBasicBlock &block : *bottomUp[i]) {
      for (SILInstruction &inst : block) {
        if (auto *ref = dyn_cast<FunctionRefBaseInst>(&inst)) {
          if (SILFunction *closure = getLinkedClosure(bottomUp[i], ref))
            join(closure);
        }
        if (auto apply = ApplySite::isa(&inst)) {
          if (SILFunction *closure = getScopedClosure(apply))
            join(closure);
        }
        BottomUpFunctionOrder::visitCallees(
            inst, bca, [&](SILFunction *callee) {
              auto it = bottomUpIndex.find(callee);
              if (it != bottomUpIndex.end() && it->second != i)
                callEdges.push_back({i, it->second});
            });
      }
    }
  }
  return callEdges;
}

// The constructor runs in four stages. Structures are indexed by a
// definition's position in bottom-up order. Union-find names each closure
// component by its "leader", its smallest position.
//   1. Number function definitions in bottom-up order.
//   2. Scan every instruction once, building closure components (scopes
//      with their closures) and recording call edges.
//   3. Contract the call graph to one node per component, its leader.
//   4. Take the SCCs of that graph, callees first. Each SCC is a group.
//
// For example: take two functions that each pass a closure to a helper, where
// each closure calls the other function.
//
//   func f() { var x = 0; helper { x += 1; g() } }   // closure cf
//   func g() { var y = 0; helper { y += 1; f() } }   // closure cg
//
// {f, cf} and {g, cg} are closure components. No function is on a call
// cycle, but cf calls g and cg calls f, so each component calls the other and
// neither can be scheduled first. Stage 4 puts all four in one group.
//
//   functions             components (stage 3)    group (stage 4)
//
//   f ~~> cf              [f cf] --> [g cg]       [f cf g cg]
//   ^      |                ^          |
//   |      v                +----------+
//   cg <~~ g
//
//   ~~> closure edge, from scope to closure; the other arrows are call edges.
ClosureGroupSchedule::ClosureGroupSchedule(SILModule &module,
                                           BasicCalleeAnalysis *bca) {
  // 1. Number the definitions. Declarations have no body to schedule.
  BottomUpFunctionOrder order(module, bca);
  for (SILFunction *f : order.getFunctions()) {
    if (!f->isDefinition())
      continue;
    bottomUpIndex[f] = bottomUp.size();
    bottomUp.push_back(f);
  }
  unsigned n = bottomUp.size();

  // 2. Closure components and call edges.
  llvm::IntEqClasses components(n);
  auto callEdges = collectEdges(bottomUp, bottomUpIndex, bca, components);
  componentOf.resize(n);
  llvm::SmallVector<llvm::SmallVector<unsigned, 4>, 32> componentMembers(n);
  for (unsigned i = 0; i != n; ++i) {
    componentOf[i] = components.findLeader(i);
    componentMembers[componentOf[i]].push_back(i);
  }

  // 3. The call graph between components.
  ComponentGraph graph(callEdges, componentOf);

  // 4. scc_iterator emits an SCC only after every SCC it calls into, so groups
  // come out callees first. The last SCC holds only the root.
  unsigned numScheduled = 0;
  for (auto scc = llvm::scc_begin(&graph); !scc.isAtEnd(); ++scc) {
    const std::vector<ComponentGraph::Node *> &sccNodes = *scc;
    if (sccNodes.front() == graph.getRoot())
      continue;
    llvm::SmallVector<unsigned, 8> members;
    for (ComponentGraph::Node *node : sccNodes)
      llvm::append_range(members, componentMembers[node - graph.nodes.data()]);
    llvm::sort(members); // Members keep bottom-up order.
    Group &group = groups.emplace_back();
    for (unsigned i : members)
      group.push_back(bottomUp[i]);
    numScheduled += members.size();
  }
  assert(numScheduled == n && "a component is unreachable from the root");
  (void)numScheduled;
}

void ClosureGroupSchedule::print(llvm::raw_ostream &os) const {
  for (unsigned i = 0, e = groups.size(); i != e; ++i) {
    os << "group " << i << "\n";
    for (SILFunction *f : groups[i]) {
      unsigned component = componentOf[bottomUpIndex.lookup(f)];
      os << "  [" << bottomUp[component]->getName() << "] " << f->getName()
         << "\n";
    }
  }
}

namespace swift::test {
// Dumps the module's closure groups in schedule order, each member prefixed
// by its closure component's leader in brackets.
static FunctionTest ClosureGroupScheduleTest(
    "closure_group_schedule", [](auto &function, auto &arguments, auto &test) {
      auto *bca = test.template getAnalysis<BasicCalleeAnalysis>();
      ClosureGroupSchedule schedule(function.getModule(), bca);
      schedule.print(llvm::outs());
    });
} // end namespace swift::test
