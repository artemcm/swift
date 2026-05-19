//===--- SILGenRequests.cpp - Requests for SIL Generation  ----------------===//
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

#include "swift/AST/SILGenRequests.h"
#include "SILGen.h"
#include "swift/AST/ASTContext.h"
#include "swift/AST/Attr.h"
#include "swift/AST/AutoDiff.h"
#include "swift/AST/Decl.h"
#include "swift/AST/DiagnosticsSIL.h"
#include "swift/AST/FileUnit.h"
#include "swift/AST/Module.h"
#include "swift/AST/ParameterList.h"
#include "swift/AST/PropertyWrappers.h"
#include "swift/AST/SourceFile.h"
#include "swift/Basic/Assertions.h"
#include "swift/SIL/SILDifferentiabilityWitness.h"
#include "swift/SIL/SILFunction.h"
#include "swift/SIL/SILModule.h"
#include "swift/SILOptimizer/PassManager/PassManager.h"
#include "swift/SILOptimizer/PassManager/PassPipeline.h"
#include "swift/Subsystems.h"
#include "llvm/Support/Debug.h"

#define DEBUG_TYPE "silgen-requests"

using namespace swift;

#ifndef NDEBUG
/// Indentation depth for nested request tracing.
static unsigned requestTraceDepth = 0;
static llvm::raw_ostream &traceIndent() {
  for (unsigned i = 0; i < requestTraceDepth; ++i)
    llvm::dbgs() << "  ";
  return llvm::dbgs();
}
struct TraceScope {
  bool active;
  TraceScope() : active(llvm::DebugFlag && llvm::isCurrentDebugType(DEBUG_TYPE)) {
    if (active) ++requestTraceDepth;
  }
  ~TraceScope() { if (active) --requestTraceDepth; }
};
#else
struct TraceScope { };
#endif

namespace swift {
// Implement the SILGen type zone (zone 12).
#define SWIFT_TYPEID_ZONE SILGen
#define SWIFT_TYPEID_HEADER "swift/AST/SILGenTypeIDZone.def"
#include "swift/Basic/ImplementTypeIDZone.h"
#undef SWIFT_TYPEID_ZONE
#undef SWIFT_TYPEID_HEADER
} // end namespace swift

void swift::simple_display(llvm::raw_ostream &out,
                           const ASTLoweringDescriptor &desc) {
  auto *MD = desc.context.dyn_cast<ModuleDecl *>();
  auto *unit = desc.context.dyn_cast<FileUnit *>();
  if (MD) {
    out << "Lowering AST to SIL for module " << MD->getName();
  } else {
    assert(unit);
    out << "Lowering AST to SIL for file ";
    simple_display(out, unit);
  }
}

SourceLoc swift::extractNearestSourceLoc(const ASTLoweringDescriptor &desc) {
  return SourceLoc();
}

evaluator::DependencySource ASTLoweringRequest::readDependencySource(
    const evaluator::DependencyRecorder &e) const {
  auto &desc = std::get<0>(getStorage());

  // We don't track dependencies in whole-module mode.
  if (isa<ModuleDecl *>(desc.context)) {
    return nullptr;
  }

  // If we have a single source file, it's the source of dependencies.
  return dyn_cast<SourceFile>(cast<FileUnit *>(desc.context));
}

ArrayRef<FileUnit *> ASTLoweringDescriptor::getFilesToEmit() const {
  // If we have a specific set of SILDeclRefs to emit, we don't emit any whole
  // files.
  if (SourcesToEmit)
    return {};

  if (auto *mod = context.dyn_cast<ModuleDecl *>())
    return mod->getFiles();

  // For a single file, we can form an ArrayRef that points at its storage in
  // the union.
  return llvm::ArrayRef(*context.getAddrOfPtr1());
}

SourceFile *ASTLoweringDescriptor::getSourceFileToParse() const {
#ifndef NDEBUG
  auto sfCount = llvm::count_if(getFilesToEmit(), [](FileUnit *file) {
    return isa<SourceFile>(file);
  });
  auto silFileCount = llvm::count_if(getFilesToEmit(), [](FileUnit *file) {
    auto *SF = dyn_cast<SourceFile>(file);
    return SF && SF->Kind == SourceFileKind::SIL;
  });
  assert(silFileCount == 0 || (silFileCount == 1 && sfCount == 1) &&
         "Cannot currently mix a .sil file with other SourceFiles");
#endif

  for (auto *file : getFilesToEmit()) {
    // Skip other kinds of files.
    auto *SF = dyn_cast<SourceFile>(file);
    if (!SF)
      continue;

    // Given the above precondition that a .sil file isn't mixed with other
    // SourceFiles, we can return a SIL file if we have it, or return nullptr.
    if (SF->Kind == SourceFileKind::SIL) {
      return SF;
    } else {
      return nullptr;
    }
  }
  return nullptr;
}

SILFunction *
SILFunctionInterfaceRequest::evaluate(Evaluator &evaluator,
                                      SILDeclRef constant) const {
  LLVM_DEBUG(traceIndent() << "-> SILFunctionInterfaceRequest: ";
             constant.print(llvm::dbgs()); llvm::dbgs() << "\n");
  TraceScope _ts1;
  auto *SGM = constant.getASTContext().getActiveSILGenModule();
  ASSERT(SGM && "SILFunctionInterfaceRequest evaluated outside SILGen scope");
  return SGM->getFunction(constant, NotForDefinition);
}

SILFunction *
SILFunctionBodyRequest::evaluate(Evaluator &evaluator,
                                 SILDeclRef constant) const {
  LLVM_DEBUG(traceIndent() << "-> SILFunctionBodyRequest: ";
             constant.print(llvm::dbgs()); llvm::dbgs() << "\n");
  TraceScope _ts2;
  auto *SGM = constant.getASTContext().getActiveSILGenModule();
  ASSERT(SGM && "SILFunctionBodyRequest evaluated outside SILGen scope");

  // Get or create the function declaration via the interface request.
  auto *f = evaluateOrFatal(evaluator,
                            SILFunctionInterfaceRequest{constant});

  // If the function already has a body (e.g., deserialized from a
  // cross-module .swiftmodule or already emitted via the non-request
  // path), skip emission. Do NOT upgrade linkage: cross-module
  // functions should retain their external linkage.
  if (!f->empty())
    return f;

  // The interface request uses NotForDefinition linkage. Upgrade to
  // definition linkage before emitting the body.
  if (isAvailableExternally(f->getLinkage()))
    f->setLinkage(constant.getLinkage(ForDefinition));

  // Emit the function body.
  if (!f->empty())
    return f;

  // Emit the function body. Callee references discovered during emission
  // are created via SILGenModule::getFunction and may be queued in
  // pendingForcedFunctions. The drain loop in ASTLoweringRequest handles
  // emitting those bodies.
  SGM->emitFunctionDefinition(constant, f);
  return f;
}

SILFunction *
CleanedSILFunctionRequest::evaluate(Evaluator &evaluator,
                                    SILDeclRef constant) const {
  LLVM_DEBUG(traceIndent() << "-> CleanedSILFunctionRequest: ";
             constant.print(llvm::dbgs()); llvm::dbgs() << "\n");
  TraceScope _ts3;
  auto *f = evaluateOrFatal(evaluator,
                            SILFunctionBodyRequest{constant});
  if (f->isAlreadyCanonical())
    return f;

  // Clear pass-notification flags set during SIL construction.
  // SILGenCleanup handles these concerns unconditionally, but the pass
  // manager asserts flags are false before starting.
  f->setNeedBreakInfiniteLoops(false);
  f->setNeedCompleteLifetimes(false);

  auto &silMod = f->getModule();
  SILPassManager PM(&silMod, /*isMandatory=*/true, /*IRMod=*/nullptr);
  PM.executePassPipelinePlan(
      SILPassPipelinePlan::getSILGenPassPipeline(silMod.getOptions()),
      f);
  return f;
}

SILFunction *
DiagnosedSILFunctionRequest::evaluate(Evaluator &evaluator,
                                      SILDeclRef constant) const {
  LLVM_DEBUG(traceIndent() << "-> DiagnosedSILFunctionRequest: ";
             constant.print(llvm::dbgs()); llvm::dbgs() << "\n");
  TraceScope _ts4;
  auto *f = evaluateOrFatal(evaluator,
                            CleanedSILFunctionRequest{constant});
  if (f->isAlreadyCanonical())
    return f;

  auto &silMod = f->getModule();
  SILPassManager PM(&silMod, /*isMandatory=*/true, /*IRMod=*/nullptr);
  PM.executePassPipelinePlan(
      SILPassPipelinePlan::getFunctionOnlyDiagnosticPassPipeline(
          silMod.getOptions()),
      f);
  return f;
}

SILFunction *
CanonicalSILFunctionRequest::evaluate(Evaluator &evaluator,
                                      SILDeclRef constant) const {
  LLVM_DEBUG(traceIndent() << "-> CanonicalSILFunctionRequest: ";
             constant.print(llvm::dbgs()); llvm::dbgs() << "\n");
  TraceScope _ts5;
  auto *f = evaluateOrFatal(evaluator,
                            DiagnosedSILFunctionRequest{constant});
  if (!f->isAlreadyCanonical())
    f->setFunctionStage(SILStage::Canonical);
  return f;
}

void CanonicalSILFunctionRequest::diagnoseCycle(
    DiagnosticEngine &diags) const {
  auto constant = std::get<0>(getStorage());
  if (constant.hasDecl()) {
    if (auto *afd = dyn_cast<AbstractFunctionDecl>(constant.getDecl())) {
      if (afd->isTransparent()) {
        diags.diagnose(afd->getLoc(), diag::circular_transparent);
        return;
      }
    }
    diags.diagnose(constant.getDecl()->getLoc(), diag::circular_inlineAlways);
  }
}

void CanonicalSILFunctionRequest::noteCycleStep(
    DiagnosticEngine &diags) const {
  auto constant = std::get<0>(getStorage());
  if (constant.hasDecl())
    diags.diagnose(constant.getDecl()->getLoc(), diag::note_while_inlining);
}

// MARK: Auxiliary-emission requests

evaluator::SideEffect
AuxiliaryDeclEmissionRequest::evaluate(Evaluator &evaluator,
                                       AbstractFunctionDecl *afd) const {
  LLVM_DEBUG(traceIndent() << "-> AuxiliaryDeclEmissionRequest: "
                           << afd->getName() << "\n");
  TraceScope _ts;
  auto *SGM = afd->getASTContext().getActiveSILGenModule();
  ASSERT(SGM &&
         "AuxiliaryDeclEmissionRequest evaluated outside SILGen scope");

  // Mirror legacy emitAbstractFuncDecl preconditions.
  ASSERT(ABIRoleInfo(afd).providesAPI() &&
         "AuxiliaryDeclEmissionRequest evaluated on ABI-only decl");

  (void)evaluateOrDefault(evaluator, ArgumentGeneratorsRequest{afd}, {});
  (void)evaluateOrDefault(evaluator, CDeclThunkRequest{afd}, {});
  (void)evaluateOrDefault(evaluator, DistributedThunkRequest{afd}, {});
  (void)evaluateOrDefault(evaluator, BackDeploymentRequest{afd}, {});
  for (auto *derivAttr : afd->getAttrs().getAttributes<DerivativeAttr>()) {
    (void)evaluateOrDefault(
        evaluator,
        SILDifferentiabilityWitnessRequest{afd, derivAttr}, nullptr);
  }
  return {};
}

evaluator::SideEffect
ArgumentGeneratorsRequest::evaluate(Evaluator &evaluator,
                                    AbstractFunctionDecl *afd) const {
  LLVM_DEBUG(traceIndent() << "-> ArgumentGeneratorsRequest: "
                           << afd->getName() << "\n");
  TraceScope _ts;
  auto *SGM = afd->getASTContext().getActiveSILGenModule();
  ASSERT(SGM);

  unsigned i = 0;
  for (auto *param : *afd->getParameters()) {
    if (param->isDefaultArgument()) {
      auto kind = param->getDefaultArgumentKind();
      if (kind == DefaultArgumentKind::Normal ||
          kind == DefaultArgumentKind::StoredProperty) {
        auto ref = SILDeclRef::getDefaultArgGenerator(afd, i);
        (void)evaluateOrDefault(evaluator,
                                CanonicalSILFunctionRequest{ref}, nullptr);
      }
    }
    if (param->hasExternalPropertyWrapper()) {
      auto initInfo = param->getPropertyWrapperInitializerInfo();
      if (initInfo.hasInitFromWrappedValue()) {
        auto ref =
            SILDeclRef(param,
                       SILDeclRef::Kind::PropertyWrapperBackingInitializer);
        (void)evaluateOrDefault(evaluator,
                                CanonicalSILFunctionRequest{ref}, nullptr);
      }
      if (initInfo.hasInitFromProjectedValue()) {
        auto ref = SILDeclRef(
            param,
            SILDeclRef::Kind::PropertyWrapperInitFromProjectedValue);
        (void)evaluateOrDefault(evaluator,
                                CanonicalSILFunctionRequest{ref}, nullptr);
      }
    }
    ++i;
  }
  return {};
}

evaluator::SideEffect
CDeclThunkRequest::evaluate(Evaluator &evaluator,
                            AbstractFunctionDecl *afd) const {
  LLVM_DEBUG(traceIndent() << "-> CDeclThunkRequest: " << afd->getName()
                           << "\n");
  TraceScope _ts;
  auto *cdeclAttr = afd->getAttrs().getAttribute<CDeclAttr>();
  if (!cdeclAttr || !cdeclAttr->Underscored)
    return {};
  auto ref = SILDeclRef(afd).asForeign();
  (void)evaluateOrDefault(evaluator, CanonicalSILFunctionRequest{ref},
                          nullptr);
  return {};
}

evaluator::SideEffect
DistributedThunkRequest::evaluate(Evaluator &evaluator,
                                  AbstractFunctionDecl *afd) const {
  LLVM_DEBUG(traceIndent() << "-> DistributedThunkRequest: "
                           << afd->getName() << "\n");
  TraceScope _ts;
  auto *thunkDecl = afd->getDistributedThunk();
  if (!thunkDecl || !thunkDecl->hasBody() || thunkDecl->isBodySkipped())
    return {};
  auto ref = SILDeclRef(thunkDecl).asDistributed();
  (void)evaluateOrDefault(evaluator, CanonicalSILFunctionRequest{ref},
                          nullptr);
  return {};
}

evaluator::SideEffect
BackDeploymentRequest::evaluate(Evaluator &evaluator,
                                AbstractFunctionDecl *afd) const {
  LLVM_DEBUG(traceIndent() << "-> BackDeploymentRequest: "
                           << afd->getName() << "\n");
  TraceScope _ts;
  if (!afd->isBackDeployed())
    return {};
  auto fallback = SILDeclRef(afd).asBackDeploymentKind(
      SILDeclRef::BackDeploymentKind::Fallback);
  (void)evaluateOrDefault(evaluator,
                          CanonicalSILFunctionRequest{fallback}, nullptr);
  auto thunk = SILDeclRef(afd).asBackDeploymentKind(
      SILDeclRef::BackDeploymentKind::Thunk);
  (void)evaluateOrDefault(evaluator,
                          CanonicalSILFunctionRequest{thunk}, nullptr);
  return {};
}

SILDifferentiabilityWitness *
SILDifferentiabilityWitnessRequest::evaluate(
    Evaluator &evaluator, AbstractFunctionDecl *afd,
    DerivativeAttr *derivAttr) const {
  LLVM_DEBUG(traceIndent() << "-> SILDifferentiabilityWitnessRequest: "
                           << afd->getName() << "\n");
  TraceScope _ts;
  auto *SGM = afd->getASTContext().getActiveSILGenModule();
  ASSERT(SGM);

  auto *witness = SGM->emitWitnessForDerivativeAttr(afd, derivAttr);
  if (!witness)
    return nullptr;

  // Canonicalize each derivative thunk produced by the witness emission.
  // Synthesized derivative thunks created by getOrCreateCustomDerivativeThunk
  // do not have a SILDeclRef, so they cannot flow through
  // CanonicalSILFunctionRequest. Fall back to the synthesized-aux carve-out.
  auto canonicalize = [&](SILFunction *thunk) {
    if (!thunk)
      return;
    if (auto thunkRef = thunk->getDeclRef()) {
      (void)evaluateOrDefault(evaluator,
                              CanonicalSILFunctionRequest{thunkRef}, nullptr);
    } else {
      SGM->canonicalizeSynthesizedAuxFunction(thunk);
    }
  };
  canonicalize(witness->getJVP());
  canonicalize(witness->getVJP());
  return witness;
}

// Define request evaluation functions for each of the SILGen requests.
static AbstractRequestFunction *silGenRequestFunctions[] = {
#define SWIFT_REQUEST(Zone, Name, Sig, Caching, LocOptions)                    \
  reinterpret_cast<AbstractRequestFunction *>(&Name::evaluateRequest),
#include "swift/AST/SILGenTypeIDZone.def"
#undef SWIFT_REQUEST
};

void swift::registerSILGenRequestFunctions(Evaluator &evaluator) {
  evaluator.registerRequestFunctions(Zone::SILGen,
                                     silGenRequestFunctions);
}
