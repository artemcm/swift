//===--- SILGenRequestTrace.h - On-demand SILGen request tracing -*- C++ -*-==//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
//
// Shared indentation/scope helpers for tracing the on-demand SILGen request
// chain under `-Xllvm -debug-only=silgen-requests`. Shared across the SILGen
// translation units (SILGenRequests.cpp and the per-variety thunk-body
// requests in SILGenPoly.cpp / SILGenBridging.cpp) so nested requests indent
// consistently regardless of which TU defines the evaluate.
//
//===----------------------------------------------------------------------===//

#ifndef SWIFT_SILGEN_SILGENREQUESTTRACE_H
#define SWIFT_SILGEN_SILGENREQUESTTRACE_H

#include "llvm/Support/Debug.h"
#include "llvm/Support/raw_ostream.h"

namespace swift {
namespace silgen_trace {

#ifndef NDEBUG
/// Indentation depth for nested request tracing. Defined once in
/// SILGenRequests.cpp.
extern unsigned requestTraceDepth;

/// Emit `requestTraceDepth` levels of indentation to llvm::dbgs().
inline llvm::raw_ostream &traceIndent() {
  for (unsigned i = 0; i < requestTraceDepth; ++i)
    llvm::dbgs() << "  ";
  return llvm::dbgs();
}

/// RAII guard that deepens the trace indent while a request evaluates.
struct TraceScope {
  bool active;
  TraceScope()
      : active(llvm::DebugFlag && llvm::isCurrentDebugType("silgen-requests")) {
    if (active)
      ++requestTraceDepth;
  }
  ~TraceScope() {
    if (active)
      --requestTraceDepth;
  }
};
#else
struct TraceScope {};
#endif

} // namespace silgen_trace
} // namespace swift

#endif // SWIFT_SILGEN_SILGENREQUESTTRACE_H
