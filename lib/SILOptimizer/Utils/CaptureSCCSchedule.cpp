//===--- CaptureSCCSchedule.cpp - Capture SCCs ----------------------------===//
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

#include "swift/SILOptimizer/Utils/CaptureSCCSchedule.h"
#include "swift/AST/DeclContext.h"
#include "swift/SIL/ApplySite.h"
#include "swift/SIL/SILFunction.h"
#include "swift/SIL/SILInstruction.h"
#include "swift/SIL/SILModule.h"
#include "swift/SIL/Test.h"
#include "swift/SILOptimizer/Analysis/BasicCalleeAnalysis.h"
#include "swift/SILOptimizer/Analysis/FunctionOrder.h"
#include "swift/SILOptimizer/PassManager/Transforms.h"
#include "llvm/ADT/STLExtras.h"
#include <queue>

using namespace swift;

/// R1: \p f has a parameter that receives a capture by reference.
static bool receivesCaptureByReference(SILFunction *f) {
  for (SILParameterInfo param : f->getLoweredFunctionType()->getParameters()) {
    if (param.getConvention() == ParameterConvention::Indirect_InoutAliasable)
      return true;
    if (param.getInterfaceType()->is<SILBoxType>())
      return true;
  }
  return false;
}

/// R3: \p f is a closure or a declaration inside a function body.
///
/// SILFunction::getDeclContext() is the function's own innermost context: the
/// closure expression, or the function declaration itself. A function
/// declaration is always a local context (its body), so the test is on the
/// parent.
static bool isLocalFunction(SILFunction *f) {
  DeclContext *dc = f->getDeclContext();
  if (!dc)
    return false;
  DeclContext *parent = dc->getParent();
  return parent && parent->isLocalContext();
}

bool CaptureSCCSchedule::isCaptureLink(SILFunction *caller,
                                       FunctionRefBaseInst *ref) {
  SILFunction *callee = ref->getInitiallyReferencedFunction();
  if (!callee || callee == caller || !callee->isDefinition() ||
      callee->isThunk() != IsNotThunk)
    return false;

  if (receivesCaptureByReference(callee))
    return true;

  // R2: the reference is the callee of a partial_apply.
  for (Operand *use : ref->getUses()) {
    if (auto *pai = dyn_cast<PartialApplyInst>(use->getUser()))
      if (pai->getCallee() == ref)
        return true;
  }

  return isLocalFunction(callee);
}

CaptureSCCSchedule::CaptureSCCSchedule(SILModule &module,
                                       BasicCalleeAnalysis *bca) {
  BottomUpFunctionOrder order(module, bca);
  for (SILFunction *f : order.getFunctions()) {
    if (!f->isDefinition())
      continue;
    bottomUpIndex[f] = bottomUp.size();
    bottomUp.push_back(f);
  }
  groups.grow(bottomUp.size());

  computeCaptureComponents();
  // computeSCCs follows every call edge of the bottom-up order, so it also
  // merges each SCC of the call graph.
  computeSCCs(bca);
}

void CaptureSCCSchedule::computeCaptureComponents() {
  for (SILFunction *f : bottomUp) {
    for (SILBasicBlock &block : *f) {
      for (SILInstruction &inst : block) {
        auto *ref = dyn_cast<FunctionRefBaseInst>(&inst);
        if (!ref || !isCaptureLink(f, ref))
          continue;
        auto it = bottomUpIndex.find(ref->getInitiallyReferencedFunction());
        if (it != bottomUpIndex.end())
          groups.join(bottomUpIndex[f], it->second);
      }
    }
  }
  componentOf.resize(bottomUp.size());
  for (unsigned i = 0, e = bottomUp.size(); i != e; ++i)
    componentOf[i] = groups.findLeader(i);
}

void CaptureSCCSchedule::computeSCCs(BasicCalleeAnalysis *bca) {
  unsigned n = bottomUp.size();

  // Call edges between groups (capture components), keyed by each group's
  // leader. Capture links are inside groups, so the SCCs of this graph
  // are the SCCs of the scheduling graph.
  llvm::SmallVector<llvm::SmallVector<unsigned, 4>, 32> succ(n);
  for (unsigned i = 0; i != n; ++i) {
    unsigned from = groups.findLeader(i);
    for (SILBasicBlock &block : *bottomUp[i]) {
      for (SILInstruction &inst : block) {
        BottomUpFunctionOrder::visitCallees(
            inst, bca, [&](SILFunction *callee) {
              auto it = bottomUpIndex.find(callee);
              if (it == bottomUpIndex.end())
                return;
              unsigned to = groups.findLeader(it->second);
              if (to != from)
                succ[from].push_back(to);
            });
      }
    }
  }

  // Tarjan over group leaders; merge each SCC.
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
    if (groups.findLeader(root) != root || index[root] >= 0)
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
            groups.join(v, w);
        } while (w != v);
      }
      frames.pop_back();
      if (!frames.empty()) {
        unsigned parent = frames.back().node;
        low[parent] = std::min(low[parent], low[v]);
      }
    }
  }

  // The condensation is now acyclic. Number the SCCs in the order of their
  // leaders, the earliest bottom-up members, and schedule callees first,
  // breaking ties by that number.
  groups.compress();
  unsigned numSCCs = groups.getNumClasses();
  llvm::SmallVector<llvm::SmallVector<unsigned, 4>, 32> callers(numSCCs);
  llvm::SmallVector<unsigned, 32> pendingCallees(numSCCs, 0);
  for (unsigned i = 0; i != n; ++i) {
    unsigned from = groups[i];
    for (unsigned to : succ[i]) {
      unsigned toSCC = groups[to];
      if (toSCC == from)
        continue;
      callers[toSCC].push_back(from);
      ++pendingCallees[from];
    }
  }
  std::priority_queue<unsigned, std::vector<unsigned>, std::greater<unsigned>>
      ready;
  for (unsigned u = 0; u != numSCCs; ++u)
    if (pendingCallees[u] == 0)
      ready.push(u);

  llvm::SmallVector<SCC, 32> members(numSCCs);
  for (unsigned i = 0; i != n; ++i)
    members[groups[i]].push_back(bottomUp[i]);

  while (!ready.empty()) {
    unsigned u = ready.top();
    ready.pop();
    sccs.push_back(std::move(members[u]));
    for (unsigned caller : callers[u])
      if (--pendingCallees[caller] == 0)
        ready.push(caller);
  }
  assert(sccs.size() == numSCCs && "cycle left in the condensation");
}

void CaptureSCCSchedule::print(llvm::raw_ostream &os) const {
  for (unsigned i = 0, e = sccs.size(); i != e; ++i) {
    os << "scc " << i << "\n";
    for (SILFunction *f : sccs[i]) {
      unsigned component = componentOf[bottomUpIndex.lookup(f)];
      os << "  [" << bottomUp[component]->getName() << "] " << f->getName()
         << "\n";
    }
  }
}

namespace swift::test {
// Arguments: none.
// Dumps: every scheduling SCC of the module in schedule order. Each member is
//        printed with the name of its capture component's representative in
//        brackets.
static FunctionTest CaptureSCCScheduleTest(
    "capture_scc_schedule", [](auto &function, auto &arguments, auto &test) {
      auto *bca = test.template getAnalysis<BasicCalleeAnalysis>();
      CaptureSCCSchedule schedule(function.getModule(), bca);
      schedule.print(llvm::outs());
    });
} // end namespace swift::test
