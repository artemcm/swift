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
#include "SILGenRequestTrace.h"
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
#include "swift/SIL/SILModule.h"
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
using namespace swift::silgen_trace;

#ifndef NDEBUG
unsigned swift::silgen_trace::requestTraceDepth = 0;
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

  // A body that legacy's gate declines stays a declaration (D15), with the
  // external linkage that the interface request gave it.
  if (!SGM->shouldEmitBodyOnDemand(constant))
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
  // A declaration has no body to clean.
  if (f->empty() || f->isAlreadyCanonical())
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

/// A closure or local function: a member of its scope's closure component.
/// On demand, the closure's body may not exist yet, so this reads the
/// declaration, not the body's markers (ClosureGroupSchedule's closure links).
static bool isClosureOrLocalFunction(SILDeclRef ref) {
  if (ref.getAbstractClosureExpr())
    return true;
  return ref.isFunc() && ref.hasDecl() &&
         ref.getDecl()->getDeclContext()->isLocalContext();
}

/// Add the closures and local functions that \p member references to
/// \p members, each followed by its own, depth first. That is the order in
/// which SILGen creates them, which legacy's pass order follows for functions
/// that nothing calls (see getBottomUpOrder).
static void collectClosures(Evaluator &evaluator, SILFunction *member,
                            llvm::SmallSetVector<SILFunction *, 8> &members) {
  for (auto &block : *member) {
    for (auto &inst : block) {
      auto *ref = dyn_cast<FunctionRefBaseInst>(&inst);
      if (!ref)
        continue;
      SILFunction *callee = ref->getInitiallyReferencedFunction();
      if (members.count(callee) || callee->isAlreadyCanonical())
        continue;
      SILDeclRef calleeRef = callee->getDeclRef();
      if (!calleeRef || !isClosureOrLocalFunction(calleeRef))
        continue;
      auto *closure =
          evaluateOrFatal(evaluator, CleanedSILFunctionRequest{calleeRef});
      if (closure->isDefinition() && !closure->isAlreadyCanonical()) {
        members.insert(closure);
        collectClosures(evaluator, closure, members);
      }
    }
  }
}

/// The closure component of \p root, as far as it can be found from \p root
/// on demand: \p root, then each closure and local function that a member
/// references, transitively, in the order that collectClosures finds them.
/// Each member's body is emitted and run through the SILGen pipeline. A closure
/// that another root's run already canonicalized is not a member.
static void collectClosureComponent(Evaluator &evaluator, SILFunction *root,
                                    llvm::SmallSetVector<SILFunction *, 8> &members) {
  members.insert(root);
  collectClosures(evaluator, root, members);
  // A capture edge from a member to a definition outside the component
  // would make a group pass read or write outside its group; the passes'
  // membership checks report it.
}

SILFunction *
DiagnosedSILFunctionRequest::evaluate(Evaluator &evaluator,
                                      SILDeclRef constant) const {
  LLVM_DEBUG(traceIndent() << "-> DiagnosedSILFunctionRequest: ";
             constant.print(llvm::dbgs()); llvm::dbgs() << "\n");
  TraceScope _ts4;
  auto *f = evaluateOrFatal(evaluator,
                            CleanedSILFunctionRequest{constant});
  // A declaration has no body to diagnose.
  if (f->empty() || f->isAlreadyCanonical())
    return f;

  auto &silMod = f->getModule();
  auto plan = SILPassPipelinePlan::getFunctionOnlyDiagnosticPassPipeline(
      silMod.getOptions());

  // Run the diagnostic pipeline once over f's closure component, so that the
  // closure group passes see each closure with its scope.
  llvm::SmallSetVector<SILFunction *, 8> members;
  collectClosureComponent(evaluator, f, members);
  DEBUG_WITH_TYPE("silgen-requests", {
    llvm::dbgs() << "[component] " << f->getName() << ":";
    for (SILFunction *member : members)
      llvm::dbgs() << " " << member->getName();
    llvm::dbgs() << "\n";
  });
  {
    SILPassManager PM(&silMod, /*isMandatory=*/true, /*IRMod=*/nullptr);
    PM.executePassPipelinePlan(plan, members.getArrayRef());
  }
  // The other members are diagnosed now. Mark them canonical, so that their
  // own requests skip the pipelines; CanonicalSILFunctionRequest marks f.
  for (SILFunction *member : members)
    if (member != f && member->isDefinition())
      member->setFunctionStage(SILStage::Canonical);
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
  // Only a function with a body reaches the Canonical stage.
  if (!f->empty() && !f->isAlreadyCanonical())
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

SILFunction *
CanonicalSynthesizedFunctionRequest::evaluate(Evaluator &evaluator,
                                              SILFunction *f) const {
  LLVM_DEBUG(traceIndent() << "-> CanonicalSynthesizedFunctionRequest: "
                           << f->getName() << "\n");
  TraceScope _ts;

  if (f->isAlreadyCanonical())
    return f;
  if (f->empty())
    return f;

  // Clear pass-notification flags; the pass manager asserts they're false
  // (as in CleanedSILFunctionRequest::evaluate).
  f->setNeedBreakInfiniteLoops(false);
  f->setNeedCompleteLifetimes(false);

  auto &silMod = f->getModule();
  {
    SILPassManager PM(&silMod, /*isMandatory=*/true, /*IRMod=*/nullptr);
    PM.executePassPipelinePlan(
        SILPassPipelinePlan::getSILGenPassPipeline(silMod.getOptions()), f);
  }
  {
    SILPassManager PM(&silMod, /*isMandatory=*/true, /*IRMod=*/nullptr);
    PM.executePassPipelinePlan(
        SILPassPipelinePlan::getFunctionOnlyDiagnosticPassPipeline(
            silMod.getOptions()),
        f);
  }
  f->setFunctionStage(SILStage::Canonical);
  return f;
}

// MARK: Auxiliary-emission requests

evaluator::SideEffect
AuxiliaryDeclEmissionRequest::evaluate(Evaluator &evaluator,
                                       ValueDecl *decl) const {
  LLVM_DEBUG(traceIndent() << "-> AuxiliaryDeclEmissionRequest: "
                           << decl->getName() << "\n");
  TraceScope _ts;
  auto *SGM = decl->getASTContext().getActiveSILGenModule();
  ASSERT(SGM &&
         "AuxiliaryDeclEmissionRequest evaluated outside SILGen scope");

  // Mirror legacy emitAbstractFuncDecl preconditions.
  ASSERT(ABIRoleInfo(decl).providesAPI() &&
         "AuxiliaryDeclEmissionRequest evaluated on ABI-only decl");

  (void)evaluateOrDefault(evaluator, ArgumentGeneratorsRequest{decl}, {});

  // A subscript or an enum element has only argument generators
  // (SILGenType::visitSubscriptDecl, visitEnumElementDecl).
  auto *afd = dyn_cast<AbstractFunctionDecl>(decl);
  if (!afd)
    return {};

  if (afd->getAttrs().getAttribute<CDeclAttr>())
    (void)evaluateOrDefault(evaluator, CDeclThunkRequest{afd}, {});
  if (afd->getDistributedThunk())
    (void)evaluateOrDefault(evaluator, DistributedThunkRequest{afd}, {});
  if (afd->isBackDeployed())
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
                                    ValueDecl *decl) const {
  LLVM_DEBUG(traceIndent() << "-> ArgumentGeneratorsRequest: "
                           << decl->getName() << "\n");
  TraceScope _ts;
  auto *SGM = decl->getASTContext().getActiveSILGenModule();
  ASSERT(SGM);

  // Mirror SILGenModule::emitArgumentGenerators, emitDefaultArgGenerator, and
  // emitPropertyWrapperBackingInitializer, with emitOrDelayFunction's delay
  // heuristic: a function legacy would delay is left for a reference.
  auto emitOrDelay = [&](SILDeclRef ref) {
    if (!SGM->delayFunctionOnDemand(ref))
      (void)evaluateOrDefault(evaluator, CanonicalSILFunctionRequest{ref},
                              nullptr);
  };
  auto *params = decl->getParameterList();
  if (!params)
    return {};
  unsigned i = 0;
  for (auto *param : *params) {
    if (param->isDefaultArgument()) {
      auto kind = param->getDefaultArgumentKind();
      if (kind == DefaultArgumentKind::Normal ||
          kind == DefaultArgumentKind::StoredProperty)
        emitOrDelay(SILDeclRef::getDefaultArgGenerator(decl, i));
    }
    if (param->hasExternalPropertyWrapper() &&
        !SGM->M.getOptions().SkipNonExportableDecls) {
      auto initInfo = param->getPropertyWrapperInitializerInfo();
      if (initInfo.hasInitFromWrappedValue())
        emitOrDelay(SILDeclRef(
            param, SILDeclRef::Kind::PropertyWrapperBackingInitializer));
      if (initInfo.hasInitFromProjectedValue())
        emitOrDelay(SILDeclRef(
            param, SILDeclRef::Kind::PropertyWrapperInitFromProjectedValue));
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
  auto ref = SILDeclRef(thunkDecl).getDistributedThunkDeclRef();
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
  // Legacy emitAbstractFuncDecl's condition. A destructor's fallback comes
  // from emitMoveOnlyDestructor, and a member without a body of its own has
  // nothing to use as one.
  if (!afd->isBackDeployed() || isa<DestructorDecl>(afd))
    return {};
  if (!afd->hasBody() && !afd->getAttrs().hasAttribute<BackDeployedAttr>() &&
      !(isa<AccessorDecl>(afd) && cast<AccessorDecl>(afd)
                                      ->getStorage()
                                      ->getAttrs()
                                      .hasAttribute<BackDeployedAttr>()))
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
  // Derivative thunks have no SILDeclRef, so route them through
  // CanonicalSynthesizedFunctionRequest. Idempotent safety net: normally
  // already canonicalized by the getOrCreateCustomDerivativeThunk wrapper.
  auto canonicalize = [&](SILFunction *thunk) {
    if (!thunk)
      return;
    if (auto thunkRef = thunk->getDeclRef()) {
      (void)evaluateOrDefault(evaluator,
                              CanonicalSILFunctionRequest{thunkRef}, nullptr);
    } else {
      (void)evaluateOrDefault(evaluator,
                              CanonicalSynthesizedFunctionRequest{thunk},
                              nullptr);
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
