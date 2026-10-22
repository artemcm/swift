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
#include "swift/SIL/ApplySite.h"
#include "swift/SIL/SILFunction.h"
#include "swift/SIL/SILInstruction.h"
#include "swift/SIL/SILModule.h"
#include "swift/SIL/Test.h"
#include "swift/SILOptimizer/Analysis/BasicCalleeAnalysis.h"
#include "swift/SILOptimizer/Analysis/ClosureScope.h"
#include "swift/SILOptimizer/Analysis/FunctionOrder.h"
#include "swift/SILOptimizer/PassManager/Transforms.h"
#include "llvm/ADT/IntEqClasses.h"
#include <queue>
#include <utility>

using namespace swift;

ClosureGroupSchedule::ClosureGroupSchedule(SILModule &module,
                                           BasicCalleeAnalysis *bca) {
  BottomUpFunctionOrder order(module, bca);
  for (SILFunction *f : order.getFunctions()) {
    if (!f->isDefinition())
      continue;
    bottomUpIndex[f] = bottomUp.size();
    bottomUp.push_back(f);
  }
  unsigned n = bottomUp.size();
  // Classes of bottomUp indices: closure components, then groups. A class's
  // leader is its earliest bottom-up member.
  llvm::IntEqClasses classes(n);

  // One scan of each definition: closure graph edges join closure components,
  // and call edges, the ones the bottom-up order follows, are kept for the
  // group SCCs.
  llvm::SmallVector<std::pair<unsigned, unsigned>, 64> callEdges;
  for (unsigned i = 0; i != n; ++i) {
    for (SILBasicBlock &block : *bottomUp[i]) {
      for (SILInstruction &inst : block) {
        if (auto apply = ApplySite::isa(&inst)) {
          if (SILFunction *closure = getScopedClosure(apply)) {
            auto it = bottomUpIndex.find(closure);
            if (it != bottomUpIndex.end())
              classes.join(i, it->second);
          }
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
  componentOf.resize(n);
  for (unsigned i = 0; i != n; ++i)
    componentOf[i] = classes.findLeader(i);

  // Call edges between closure components, keyed by each component's leader.
  // Closure graph edges are inside components, so the SCCs of this graph are
  // the SCCs of the scheduling graph.
  llvm::SmallVector<llvm::SmallVector<unsigned, 4>, 32> succ(n);
  for (auto [caller, callee] : callEdges) {
    unsigned from = classes.findLeader(caller);
    unsigned to = classes.findLeader(callee);
    if (to != from)
      succ[from].push_back(to);
  }

  // Tarjan over component leaders; merge each SCC.
  llvm::SmallVector<int, 32> index(n, -1), low(n, 0);
  llvm::SmallVector<bool, 32> onStack(n, false);
  llvm::SmallVector<unsigned, 32> stack;
  int counter = 0;
  // Iterative DFS to avoid deep recursion on large modules.
  struct Frame {
    unsigned node;
    unsigned nextSucc;
  };
  llvm::SmallVector<Frame, 32> frames;
  for (unsigned root = 0; root != n; ++root) {
    if (classes.findLeader(root) != root || index[root] >= 0)
      continue;
    frames.push_back({root, 0});
    index[root] = low[root] = counter++;
    stack.push_back(root);
    onStack[root] = true;
    while (!frames.empty()) {
      Frame &fr = frames.back();
      unsigned v = fr.node;
      if (fr.nextSucc < succ[v].size()) {
        unsigned w = succ[v][fr.nextSucc++];
        if (index[w] < 0) {
          index[w] = low[w] = counter++;
          stack.push_back(w);
          onStack[w] = true;
          frames.push_back({w, 0});
        } else if (onStack[w]) {
          low[v] = std::min(low[v], index[w]);
        }
        continue;
      }
      if (low[v] == index[v]) {
        unsigned w;
        do {
          w = stack.pop_back_val();
          onStack[w] = false;
          if (w != v)
            classes.join(v, w);
        } while (w != v);
      }
      frames.pop_back();
      if (!frames.empty()) {
        unsigned parent = frames.back().node;
        low[parent] = std::min(low[parent], low[v]);
      }
    }
  }

  // The condensation is now acyclic. Number the groups in the order of their
  // leaders, the earliest bottom-up members, and schedule callees first,
  // breaking ties by that number.
  classes.compress();
  unsigned numGroups = classes.getNumClasses();
  llvm::SmallVector<llvm::SmallVector<unsigned, 4>, 32> callers(numGroups);
  llvm::SmallVector<unsigned, 32> pendingCallees(numGroups, 0);
  for (unsigned i = 0; i != n; ++i) {
    unsigned from = classes[i];
    for (unsigned to : succ[i]) {
      unsigned toGroup = classes[to];
      if (toGroup == from)
        continue;
      callers[toGroup].push_back(from);
      ++pendingCallees[from];
    }
  }
  std::priority_queue<unsigned, std::vector<unsigned>, std::greater<unsigned>>
      ready;
  for (unsigned g = 0; g != numGroups; ++g)
    if (pendingCallees[g] == 0)
      ready.push(g);

  llvm::SmallVector<Group, 32> members(numGroups);
  for (unsigned i = 0; i != n; ++i)
    members[classes[i]].push_back(bottomUp[i]);

  while (!ready.empty()) {
    unsigned g = ready.top();
    ready.pop();
    groups.push_back(std::move(members[g]));
    for (unsigned caller : callers[g])
      if (--pendingCallees[caller] == 0)
        ready.push(caller);
  }
  assert(groups.size() == numGroups && "cycle left in the condensation");
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
// Arguments: none.
// Dumps: every closure group of the module in schedule order. Each member is
//        printed with the name of its closure component's representative in
//        brackets.
static FunctionTest ClosureGroupScheduleTest(
    "closure_group_schedule", [](auto &function, auto &arguments, auto &test) {
      auto *bca = test.template getAnalysis<BasicCalleeAnalysis>();
      ClosureGroupSchedule schedule(function.getModule(), bca);
      schedule.print(llvm::outs());
    });
} // end namespace swift::test
