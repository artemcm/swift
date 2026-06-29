//===--- SILGenRequests.h - SILGen Requests ---------------------*- C++ -*-===//
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
//  This file defines SILGen requests.
//
//===----------------------------------------------------------------------===//

#ifndef SWIFT_SILGEN_REQUESTS_H
#define SWIFT_SILGEN_REQUESTS_H

#include "swift/AST/ASTTypeIDs.h"
#include "swift/AST/EvaluatorDependencies.h"
#include "swift/AST/SimpleRequest.h"
#include "swift/AST/SourceFile.h"
#include "swift/AST/TBDGenRequests.h"
#include "swift/AST/Types.h"
#include "swift/SIL/AbstractionPattern.h"
#include "swift/SIL/SILDeclRef.h"
#include "swift/SIL/SILLocation.h"

namespace swift {

class LangOptions;
class ModuleDecl;
class AbstractFunctionDecl;
class DeclContext;
class DerivativeAttr;
class GenericEnvironment;
class SILDifferentiabilityWitness;
class SILFunction;
class SILModule;
class SILOptions;
class IRGenOptions;

namespace Lowering {
  class TypeConverter;
}

/// Report that a request of the given kind is being evaluated, so it
/// can be recorded by the stats reporter.
template<typename Request>
void reportEvaluatedRequest(UnifiedStatsReporter &stats,
                            const Request &request);

using SILRefsToEmit = llvm::SmallVector<SILDeclRef, 1>;

using SymbolSources = llvm::SmallVector<SymbolSource, 1>;

/// Describes a file or module to be lowered to SIL.
struct ASTLoweringDescriptor {
  llvm::PointerUnion<FileUnit *, ModuleDecl *> context;
  Lowering::TypeConverter &conv;
  const SILOptions &opts;
  const IRGenOptions *irgenOptions;

  /// A specific set of SILDeclRefs to emit. If set, only these refs will be
  /// emitted. Otherwise the entire \c context will be emitted.
  std::optional<SymbolSources> SourcesToEmit;

  friend llvm::hash_code hash_value(const ASTLoweringDescriptor &owner) {
    return llvm::hash_combine(owner.context, (void *)&owner.conv,
                              (void *)&owner.opts, owner.SourcesToEmit);
  }

  friend bool operator==(const ASTLoweringDescriptor &lhs,
                         const ASTLoweringDescriptor &rhs) {
    return lhs.context == rhs.context && &lhs.conv == &rhs.conv &&
           &lhs.opts == &rhs.opts && lhs.SourcesToEmit == rhs.SourcesToEmit;
  }

  friend bool operator!=(const ASTLoweringDescriptor &lhs,
                         const ASTLoweringDescriptor &rhs) {
    return !(lhs == rhs);
  }

public:
  static ASTLoweringDescriptor
  forFile(FileUnit &sf, Lowering::TypeConverter &conv, const SILOptions &opts,
          std::optional<SymbolSources> SourcesToEmit = std::nullopt,
          const IRGenOptions *irgenOptions = nullptr) {
    return ASTLoweringDescriptor{&sf, conv, opts, irgenOptions,
                                 std::move(SourcesToEmit)};
  }

  static ASTLoweringDescriptor
  forWholeModule(ModuleDecl *mod, Lowering::TypeConverter &conv,
                 const SILOptions &opts,
                 std::optional<SymbolSources> SourcesToEmit = std::nullopt,
                 const IRGenOptions *irgenOptions = nullptr) {
    return ASTLoweringDescriptor{mod, conv, opts, irgenOptions,
                                 std::move(SourcesToEmit)};
  }

  /// Retrieves the files to generate SIL for. If the descriptor is configured
  /// only to emit a specific set of SILDeclRefs, this will be empty.
  ArrayRef<FileUnit *> getFilesToEmit() const;

  /// If the module or file contains SIL that needs parsing, returns the file
  /// to be parsed, or \c nullptr if parsing isn't required.
  SourceFile *getSourceFileToParse() const;
};

void simple_display(llvm::raw_ostream &out, const ASTLoweringDescriptor &d);

SourceLoc extractNearestSourceLoc(const ASTLoweringDescriptor &desc);

/// Lowers a file or module to SIL. In most cases this involves transforming
/// a file's AST into SIL, through SILGen. However it can also handle files
/// containing SIL in textual or binary form, which will be parsed or
/// deserialized as needed.
class ASTLoweringRequest
    : public SimpleRequest<
          ASTLoweringRequest, std::unique_ptr<SILModule>(ASTLoweringDescriptor),
          RequestFlags::Uncached | RequestFlags::DependencySource> {
public:
  using SimpleRequest::SimpleRequest;

private:
  friend SimpleRequest;

  // Evaluation.
  std::unique_ptr<SILModule> evaluate(Evaluator &evaluator,
                                      ASTLoweringDescriptor desc) const;

public:
  // Incremental dependencies.
  evaluator::DependencySource
  readDependencySource(const evaluator::DependencyRecorder &) const;
};

/// Parses a .sil file into a SILModule.
class ParseSILModuleRequest
    : public SimpleRequest<ParseSILModuleRequest,
                           std::unique_ptr<SILModule>(ASTLoweringDescriptor),
                           RequestFlags::Uncached> {
public:
  using SimpleRequest::SimpleRequest;

private:
  friend SimpleRequest;

  // Evaluation.
  std::unique_ptr<SILModule> evaluate(Evaluator &evaluator,
                                      ASTLoweringDescriptor desc) const;
};

/// Creates a SILFunction declaration (empty body) for a given SILDeclRef,
/// with correct lowered type, linkage, generic environment, and attributes.
/// The function is registered in SILModule's function table but has no body.
///
/// This is the "interface" half of function emission. SILFunctionBodyRequest
/// depends on this request to obtain the declaration before filling in the body.
class SILFunctionInterfaceRequest
    : public SimpleRequest<SILFunctionInterfaceRequest,
                           SILFunction *(SILDeclRef),
                           RequestFlags::Cached> {
public:
  using SimpleRequest::SimpleRequest;

  bool isCached() const { return true; }

private:
  friend SimpleRequest;

  SILFunction *evaluate(Evaluator &evaluator, SILDeclRef constant) const;
};

/// Emits a single function body on demand, producing Raw SIL. Depends on
/// SILFunctionInterfaceRequest for the function declaration. Callee references
/// discovered during body emission are created via SILGenModule::getFunction
/// and may be queued in pendingForcedFunctions; the caller
/// (ASTLoweringRequest) is responsible for draining that queue
/// and firing SILFunctionBodyRequest for each discovered callee.
class SILFunctionBodyRequest
    : public SimpleRequest<SILFunctionBodyRequest,
                           SILFunction *(SILDeclRef),
                           RequestFlags::Cached> {
public:
  using SimpleRequest::SimpleRequest;

  bool isCached() const { return true; }

private:
  friend SimpleRequest;

  SILFunction *evaluate(Evaluator &evaluator, SILDeclRef constant) const;
};

/// Runs the SILGen cleanup pipeline on a single function, producing
/// cleaned Raw SIL. Depends on SILFunctionBodyRequest.
class CleanedSILFunctionRequest
    : public SimpleRequest<CleanedSILFunctionRequest,
                           SILFunction *(SILDeclRef),
                           RequestFlags::Cached> {
public:
  using SimpleRequest::SimpleRequest;

  bool isCached() const { return true; }

private:
  friend SimpleRequest;

  SILFunction *evaluate(Evaluator &evaluator, SILDeclRef constant) const;
};

/// Runs the function-only mandatory diagnostic pipeline on a single
/// function, producing diagnosed SIL. Depends on
/// CleanedSILFunctionRequest.
class DiagnosedSILFunctionRequest
    : public SimpleRequest<DiagnosedSILFunctionRequest,
                           SILFunction *(SILDeclRef),
                           RequestFlags::Cached> {
public:
  using SimpleRequest::SimpleRequest;

  bool isCached() const { return true; }

private:
  friend SimpleRequest;

  SILFunction *evaluate(Evaluator &evaluator, SILDeclRef constant) const;
};

/// Sets the per-function stage to Canonical after all mandatory passes
/// have been applied. Depends on DiagnosedSILFunctionRequest.
/// Implements cycle diagnostics for circular @transparent / @inline(__always).
class CanonicalSILFunctionRequest
    : public SimpleRequest<CanonicalSILFunctionRequest,
                           SILFunction *(SILDeclRef),
                           RequestFlags::Cached> {
public:
  using SimpleRequest::SimpleRequest;

  bool isCached() const { return true; }

  void diagnoseCycle(DiagnosticEngine &diags) const;
  void noteCycleStep(DiagnosticEngine &diags) const;

private:
  friend SimpleRequest;

  SILFunction *evaluate(Evaluator &evaluator, SILDeclRef constant) const;
};

/// Orchestrates the emission of all auxiliary SIL functions and
/// SIL-module side effects associated with an AbstractFunctionDecl.
/// Mirrors the structure of legacy `SILGenModule::emitAbstractFuncDecl`
/// but routes each auxiliary kind through a per-feature sub-request,
/// which in turn fires `CanonicalSILFunctionRequest` for each
/// auxiliary SILDeclRef.
class AuxiliaryDeclEmissionRequest
    : public SimpleRequest<AuxiliaryDeclEmissionRequest,
                           evaluator::SideEffect(AbstractFunctionDecl *),
                           RequestFlags::Cached> {
public:
  using SimpleRequest::SimpleRequest;

  bool isCached() const { return true; }

private:
  friend SimpleRequest;

  evaluator::SideEffect
  evaluate(Evaluator &evaluator, AbstractFunctionDecl *afd) const;
};

/// Emits default-argument generators and property-wrapper backing
/// initializers for an AbstractFunctionDecl, by walking the parameter
/// list in order and firing CanonicalSILFunctionRequest for each.
class ArgumentGeneratorsRequest
    : public SimpleRequest<ArgumentGeneratorsRequest,
                           evaluator::SideEffect(AbstractFunctionDecl *),
                           RequestFlags::Cached> {
public:
  using SimpleRequest::SimpleRequest;

  bool isCached() const { return true; }

private:
  friend SimpleRequest;

  evaluator::SideEffect
  evaluate(Evaluator &evaluator, AbstractFunctionDecl *afd) const;
};

/// Emits the native-to-foreign thunk for a `@_cdecl` (Underscored)
/// declaration. No-op for other declarations.
class CDeclThunkRequest
    : public SimpleRequest<CDeclThunkRequest,
                           evaluator::SideEffect(AbstractFunctionDecl *),
                           RequestFlags::Cached> {
public:
  using SimpleRequest::SimpleRequest;

  bool isCached() const { return true; }

private:
  friend SimpleRequest;

  evaluator::SideEffect
  evaluate(Evaluator &evaluator, AbstractFunctionDecl *afd) const;
};

/// Emits the distributed thunk for a `@distributed` declaration.
/// No-op for non-distributed declarations.
class DistributedThunkRequest
    : public SimpleRequest<DistributedThunkRequest,
                           evaluator::SideEffect(AbstractFunctionDecl *),
                           RequestFlags::Cached> {
public:
  using SimpleRequest::SimpleRequest;

  bool isCached() const { return true; }

private:
  friend SimpleRequest;

  evaluator::SideEffect
  evaluate(Evaluator &evaluator, AbstractFunctionDecl *afd) const;
};

/// Emits the back-deployment fallback and dispatch thunk for a
/// `@backDeployed` declaration. No-op for declarations without the
/// attribute.
class BackDeploymentRequest
    : public SimpleRequest<BackDeploymentRequest,
                           evaluator::SideEffect(AbstractFunctionDecl *),
                           RequestFlags::Cached> {
public:
  using SimpleRequest::SimpleRequest;

  bool isCached() const { return true; }

private:
  friend SimpleRequest;

  evaluator::SideEffect
  evaluate(Evaluator &evaluator, AbstractFunctionDecl *afd) const;
};

/// Emits a SILDifferentiabilityWitness registered by a single
/// `@derivative(of:)` attribute. Returns the witness pointer, or
/// nullptr if creation failed. Canonicalizes the resulting JVP/VJP
/// derivative thunks via CanonicalSILFunctionRequest (or
/// CanonicalSynthesizedFunctionRequest for thunks lacking a
/// SILDeclRef).
class SILDifferentiabilityWitnessRequest
    : public SimpleRequest<SILDifferentiabilityWitnessRequest,
                           SILDifferentiabilityWitness *(
                               AbstractFunctionDecl *,
                               DerivativeAttr *),
                           RequestFlags::Cached> {
public:
  using SimpleRequest::SimpleRequest;

  bool isCached() const { return true; }

private:
  friend SimpleRequest;

  SILDifferentiabilityWitness *
  evaluate(Evaluator &evaluator, AbstractFunctionDecl *afd,
           DerivativeAttr *derivAttr) const;
};

/// Canonicalizes a synthesized SILFunction with no SILDeclRef (reabstraction /
/// custom-derivative thunks): runs the cleanup + function-only diagnostic
/// pipelines and sets its stage to Canonical. Keyed on the SILFunction*, since
/// these never flow through CanonicalSILFunctionRequest.
class CanonicalSynthesizedFunctionRequest
    : public SimpleRequest<CanonicalSynthesizedFunctionRequest,
                           SILFunction *(SILFunction *),
                           RequestFlags::Cached> {
public:
  using SimpleRequest::SimpleRequest;

  bool isCached() const { return true; }

private:
  friend SimpleRequest;

  SILFunction *evaluate(Evaluator &evaluator, SILFunction *f) const;
};

// Phase 5.6: each relocates one thunk-body builder behind an Uncached request
// keyed on its inputs (getOrCreateReabstractionThunk + the thunk->empty() guard
// are the cache). Identity (hash/eq) = the mangled-name determinants; the rest
// are build inputs.

/// ObjC-block-to-Swift-closure thunk body (emitBlockToFunc).
struct BlockToFuncThunkBodyDescriptor {
  // Identity:
  CanSILFunctionType thunkTy;
  CanSILFunctionType loweredBlockTy;
  CanSILFunctionType loweredFuncUnsubstTy;
  // Build-only:
  CanAnyFunctionType blockType;
  CanAnyFunctionType funcType;
  GenericEnvironment *genericEnv;
  DeclContext *fnDC;

  friend llvm::hash_code hash_value(const BlockToFuncThunkBodyDescriptor &d) {
    return llvm::hash_combine(d.thunkTy.getPointer(),
                              d.loweredBlockTy.getPointer(),
                              d.loweredFuncUnsubstTy.getPointer());
  }
  friend bool operator==(const BlockToFuncThunkBodyDescriptor &a,
                         const BlockToFuncThunkBodyDescriptor &b) {
    return a.thunkTy == b.thunkTy && a.loweredBlockTy == b.loweredBlockTy &&
           a.loweredFuncUnsubstTy == b.loweredFuncUnsubstTy;
  }
  friend bool operator!=(const BlockToFuncThunkBodyDescriptor &a,
                         const BlockToFuncThunkBodyDescriptor &b) {
    return !(a == b);
  }
};
void simple_display(llvm::raw_ostream &out,
                    const BlockToFuncThunkBodyDescriptor &d);
SourceLoc extractNearestSourceLoc(const BlockToFuncThunkBodyDescriptor &d);

class BlockToFuncThunkBodyRequest
    : public SimpleRequest<BlockToFuncThunkBodyRequest,
                           SILFunction *(BlockToFuncThunkBodyDescriptor),
                           RequestFlags::Uncached> {
public:
  using SimpleRequest::SimpleRequest;

private:
  friend SimpleRequest;

  SILFunction *evaluate(Evaluator &evaluator,
                        BlockToFuncThunkBodyDescriptor desc) const;
};

/// General reabstraction thunk body (the createThunk site).
struct ReabstractionThunkBodyDescriptor {
  // Identity:
  CanSILFunctionType thunkType;
  CanSILFunctionType fromType;
  CanSILFunctionType toType;
  CanType dynamicSelfType;
  CanType globalActor;
  // Build-only:
  Lowering::AbstractionPattern inputOrigType;
  CanAnyFunctionType inputSubstType;
  Lowering::AbstractionPattern outputOrigType;
  CanAnyFunctionType outputSubstType;
  CanSILFunctionType expectedType;
  GenericEnvironment *genericEnv;
  DeclContext *fnDC;

  friend llvm::hash_code hash_value(const ReabstractionThunkBodyDescriptor &d) {
    return llvm::hash_combine(d.thunkType.getPointer(), d.fromType.getPointer(),
                              d.toType.getPointer(),
                              d.dynamicSelfType.getPointer(),
                              d.globalActor.getPointer());
  }
  friend bool operator==(const ReabstractionThunkBodyDescriptor &a,
                         const ReabstractionThunkBodyDescriptor &b) {
    return a.thunkType == b.thunkType && a.fromType == b.fromType &&
           a.toType == b.toType && a.dynamicSelfType == b.dynamicSelfType &&
           a.globalActor == b.globalActor;
  }
  friend bool operator!=(const ReabstractionThunkBodyDescriptor &a,
                         const ReabstractionThunkBodyDescriptor &b) {
    return !(a == b);
  }
};
void simple_display(llvm::raw_ostream &out,
                    const ReabstractionThunkBodyDescriptor &d);
SourceLoc extractNearestSourceLoc(const ReabstractionThunkBodyDescriptor &d);

class ReabstractionThunkBodyRequest
    : public SimpleRequest<ReabstractionThunkBodyRequest,
                           SILFunction *(ReabstractionThunkBodyDescriptor),
                           RequestFlags::Uncached> {
public:
  using SimpleRequest::SimpleRequest;

private:
  friend SimpleRequest;

  SILFunction *evaluate(Evaluator &evaluator,
                        ReabstractionThunkBodyDescriptor desc) const;
};

/// Actor-isolation-erasure thunk body (emitActorIsolationErasureThunk);
/// evaluate reconstructs the global-actor executor-precondition prolog.
struct PreconditionClosureThunkBodyDescriptor {
  // Identity:
  CanSILFunctionType thunkType;
  CanSILFunctionType fromType;
  CanSILFunctionType toType;
  CanType dynamicSelfType;
  CanType globalActor;
  // Build-only:
  CanAnyFunctionType isolatedType;
  CanAnyFunctionType nonIsolatedType;
  Type globalActorForProlog;
  GenericEnvironment *genericEnv;
  DeclContext *fnDC;
  // Call-site location (build-only). Must be threaded, not synthesized: the
  // erasure prolog bakes it into source-location operands of the precondition.
  SILLocation loc;

  friend llvm::hash_code
  hash_value(const PreconditionClosureThunkBodyDescriptor &d) {
    return llvm::hash_combine(d.thunkType.getPointer(), d.fromType.getPointer(),
                              d.toType.getPointer(),
                              d.dynamicSelfType.getPointer(),
                              d.globalActor.getPointer());
  }
  friend bool operator==(const PreconditionClosureThunkBodyDescriptor &a,
                         const PreconditionClosureThunkBodyDescriptor &b) {
    return a.thunkType == b.thunkType && a.fromType == b.fromType &&
           a.toType == b.toType && a.dynamicSelfType == b.dynamicSelfType &&
           a.globalActor == b.globalActor;
  }
  friend bool operator!=(const PreconditionClosureThunkBodyDescriptor &a,
                         const PreconditionClosureThunkBodyDescriptor &b) {
    return !(a == b);
  }
};
void simple_display(llvm::raw_ostream &out,
                    const PreconditionClosureThunkBodyDescriptor &d);
SourceLoc
extractNearestSourceLoc(const PreconditionClosureThunkBodyDescriptor &d);

class PreconditionClosureThunkBodyRequest
    : public SimpleRequest<
          PreconditionClosureThunkBodyRequest,
          SILFunction *(PreconditionClosureThunkBodyDescriptor),
          RequestFlags::Uncached> {
public:
  using SimpleRequest::SimpleRequest;

private:
  friend SimpleRequest;

  SILFunction *evaluate(Evaluator &evaluator,
                        PreconditionClosureThunkBodyDescriptor desc) const;
};

/// withoutActuallyEscaping thunk body; evaluate also sets the
/// without-actually-escaping flag.
struct WithoutActuallyEscapingThunkBodyDescriptor {
  // Identity:
  CanSILFunctionType thunkType;
  CanSILFunctionType noEscapingFnTy;
  CanSILFunctionType escapingFnTy;
  CanType dynamicSelfType;
  // Build-only:
  GenericEnvironment *genericEnv;
  DeclContext *fnDC;

  friend llvm::hash_code
  hash_value(const WithoutActuallyEscapingThunkBodyDescriptor &d) {
    return llvm::hash_combine(d.thunkType.getPointer(),
                              d.noEscapingFnTy.getPointer(),
                              d.escapingFnTy.getPointer(),
                              d.dynamicSelfType.getPointer());
  }
  friend bool operator==(const WithoutActuallyEscapingThunkBodyDescriptor &a,
                         const WithoutActuallyEscapingThunkBodyDescriptor &b) {
    return a.thunkType == b.thunkType && a.noEscapingFnTy == b.noEscapingFnTy &&
           a.escapingFnTy == b.escapingFnTy &&
           a.dynamicSelfType == b.dynamicSelfType;
  }
  friend bool operator!=(const WithoutActuallyEscapingThunkBodyDescriptor &a,
                         const WithoutActuallyEscapingThunkBodyDescriptor &b) {
    return !(a == b);
  }
};
void simple_display(llvm::raw_ostream &out,
                    const WithoutActuallyEscapingThunkBodyDescriptor &d);
SourceLoc
extractNearestSourceLoc(const WithoutActuallyEscapingThunkBodyDescriptor &d);

class WithoutActuallyEscapingThunkBodyRequest
    : public SimpleRequest<
          WithoutActuallyEscapingThunkBodyRequest,
          SILFunction *(WithoutActuallyEscapingThunkBodyDescriptor),
          RequestFlags::Uncached> {
public:
  using SimpleRequest::SimpleRequest;

private:
  friend SimpleRequest;

  SILFunction *evaluate(Evaluator &evaluator,
                        WithoutActuallyEscapingThunkBodyDescriptor desc) const;
};

/// Swift-closure-to-ObjC-block thunk body (emitFuncToBlock).
struct FuncToBlockThunkBodyDescriptor {
  // Identity:
  CanSILFunctionType invokeTy;
  CanSILFunctionType loweredFuncUnsubstTy;
  CanSILFunctionType loweredBlockTy;
  // Build-only:
  CanAnyFunctionType funcType;
  CanAnyFunctionType blockType;
  CanSILBlockStorageType storageTy;
  bool useWithoutEscapingVerification;
  GenericEnvironment *genericEnv;
  DeclContext *fnDC;

  friend llvm::hash_code hash_value(const FuncToBlockThunkBodyDescriptor &d) {
    return llvm::hash_combine(d.invokeTy.getPointer(),
                              d.loweredFuncUnsubstTy.getPointer(),
                              d.loweredBlockTy.getPointer());
  }
  friend bool operator==(const FuncToBlockThunkBodyDescriptor &a,
                         const FuncToBlockThunkBodyDescriptor &b) {
    return a.invokeTy == b.invokeTy &&
           a.loweredFuncUnsubstTy == b.loweredFuncUnsubstTy &&
           a.loweredBlockTy == b.loweredBlockTy;
  }
  friend bool operator!=(const FuncToBlockThunkBodyDescriptor &a,
                         const FuncToBlockThunkBodyDescriptor &b) {
    return !(a == b);
  }
};
void simple_display(llvm::raw_ostream &out,
                    const FuncToBlockThunkBodyDescriptor &d);
SourceLoc extractNearestSourceLoc(const FuncToBlockThunkBodyDescriptor &d);

class FuncToBlockThunkBodyRequest
    : public SimpleRequest<FuncToBlockThunkBodyRequest,
                           SILFunction *(FuncToBlockThunkBodyDescriptor),
                           RequestFlags::Uncached> {
public:
  using SimpleRequest::SimpleRequest;

private:
  friend SimpleRequest;

  SILFunction *evaluate(Evaluator &evaluator,
                        FuncToBlockThunkBodyDescriptor desc) const;
};

/// The zone number for SILGen.
#define SWIFT_TYPEID_ZONE SILGen
#define SWIFT_TYPEID_HEADER "swift/AST/SILGenTypeIDZone.def"
#include "swift/Basic/DefineTypeIDZone.h"
#undef SWIFT_TYPEID_ZONE
#undef SWIFT_TYPEID_HEADER

 // Set up reporting of evaluated requests.
#define SWIFT_REQUEST(Zone, RequestType, Sig, Caching, LocOptions)             \
template<>                                                                     \
inline void reportEvaluatedRequest(UnifiedStatsReporter &stats,                \
                            const RequestType &request) {                      \
  ++stats.getFrontendCounters().RequestType;                                   \
}
#include "swift/AST/SILGenTypeIDZone.def"
#undef SWIFT_REQUEST

} // end namespace swift

#endif // SWIFT_SILGEN_REQUESTS_H
