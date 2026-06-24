//===--- ScanWorkState.cpp - Continuation-style scan scheduler --*- C++ -*-===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

#include "ScanWorkState.h"
#include "swift/AST/ASTContext.h"
#include "swift/ClangImporter/ClangImporter.h"
#include "swift/Serialization/ScanningLoaders.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"

using namespace swift;

ScanWorkState::ScanWorkState(ModuleDependencyScanner &scanner,
                             ModuleDependenciesCache &cache,
                             llvm::ThreadPoolInterface &pool)
    : scanner(scanner), cache(cache), pool(pool), taskGroup(pool) {}

template <class Fn> void ScanWorkState::enqueue(Fn &&work) {
  pool.async(taskGroup, [this, work = std::forward<Fn>(work)]() mutable {
    // If a sibling task has already failed, skip the body.
    if (anyError.load(std::memory_order_relaxed))
      return;
    work();
  });
}

void ScanWorkState::deferDiagnostic(StringRef sortKey,
                                    std::function<void()> emit) {
  std::lock_guard<std::mutex> guard(deferredDiagMu);
  deferredDiagnostics.emplace_back(sortKey.str(), std::move(emit));
}

// MARK: Swift import resolution

void ScanWorkState::submitSwift(const ModuleDependencyID &moduleID) {
  // Clang modules have no Swift imports; the dataflow only expands Swift nodes.
  if (!isSwiftDependencyKind(moduleID.Kind))
    return;
  {
    std::lock_guard<std::mutex> guard(pendingMu);
    if (!submittedSwiftModule.insert(moduleID.ModuleName).second)
      return;
  }
  ModuleDependencyID id = moduleID;
  enqueue([this, id]() { startSwiftImportJoin(id); });
}

void ScanWorkState::submitSwiftImportIfNeeded(
    const ScannerImportStatementInfo &importInfo, bool isTestableImport) {
  {
    std::lock_guard<std::mutex> guard(pendingMu);
    if (!submittedSwiftImport.insert(importInfo.importIdentifier).second)
      return;
  }
  ScannerImportStatementInfo info = importInfo;
  enqueue([this, info, isTestableImport]() {
    runSwiftImportTask(info, isTestableImport);
  });
}

void ScanWorkState::startSwiftImportJoin(ModuleDependencyID moduleID) {
  // Copy the module's recorded info: we read its imports without holding a
  // cache lock, and its info may be (re)written by its own continuation.
  auto moduleInfo = cache.getDependencyInfo(moduleID);

  // Fast path: if this module's Swift imports are already resolved (e.g. by a
  // prior scan or by `canImport` pre-roll warming), expand its known Swift
  // dependencies and begin its Clang join without re-scanning. This mirrors
  // the phase-based BFS fast path.
  if (!moduleInfo.getImportedSwiftDependencies().empty()) {
    for (const auto &dep : moduleInfo.getImportedSwiftDependencies())
      submitSwift(dep);
    startClangJoin(moduleID);
    return;
  }

  // Gather the distinct imported module names (excluding a self-import),
  // preserving required-then-optional order.
  struct PendingImport {
    ScannerImportStatementInfo importInfo;
    bool isTestable;
  };
  llvm::StringMap<PendingImport> distinctImports;
  llvm::SmallVector<std::string, 8> importOrder;
  auto consider = [&](const ScannerImportStatementInfo &importInfo) {
    if (moduleID.ModuleName == importInfo.importIdentifier)
      return;
    if (distinctImports.count(importInfo.importIdentifier))
      return;
    distinctImports.insert(
        {importInfo.importIdentifier,
         {importInfo,
          moduleInfo.isTestableImport(importInfo.importIdentifier)}});
    importOrder.push_back(importInfo.importIdentifier);
  };
  for (const auto &importInfo : moduleInfo.getModuleImports())
    consider(importInfo);
  for (const auto &importInfo : moduleInfo.getOptionalModuleImports())
    consider(importInfo);

  // Register the module's Swift-import join: skip names already resolved
  // (derived from the cache at finalization), wait on the rest, and dispatch
  // their by-name scans.
  llvm::SmallVector<const PendingImport *, 8> toScan;
  bool finalizeNow = false;
  {
    std::lock_guard<std::mutex> guard(swiftJoinMu);
    auto &join = swiftJoins[moduleID];
    for (const auto &name : importOrder) {
      if (cache.hasQueriedSwiftDependency(name))
        continue;
      swiftWaiters[name].push_back(moduleID);
      ++join.pending;
      toScan.push_back(&distinctImports.find(name)->second);
    }
    if (join.pending == 0) {
      join.finalized = true;
      finalizeNow = true;
    }
  }

  for (const auto *pending : toScan)
    submitSwiftImportIfNeeded(pending->importInfo, pending->isTestable);

  if (finalizeNow)
    finalizeSwiftImports(moduleID);
}

llvm::SmallVector<ModuleDependencyID, 4>
ScanWorkState::collectFinalizedWaiters(std::mutex &mu, JoinMap &joins,
                                       WaiterMap &waiters, StringRef name) {
  llvm::SmallVector<ModuleDependencyID, 4> finalized;
  std::lock_guard<std::mutex> guard(mu);
  auto waitersIt = waiters.find(name);
  if (waitersIt == waiters.end())
    return finalized;
  for (const auto &requestor : waitersIt->second) {
    auto &join = joins[requestor];
    if (--join.pending == 0 && !join.finalized) {
      join.finalized = true;
      finalized.push_back(requestor);
    }
  }
  waiters.erase(waitersIt);
  return finalized;
}

void ScanWorkState::runSwiftImportTask(ScannerImportStatementInfo importInfo,
                                       bool isTestableImport) {
  auto result = scanner.scanSwiftModuleByNameOnWorker(
      scanner.getModuleImportIdentifier(importInfo.importIdentifier),
      isTestableImport);

  // Step 1: record the result (cache writes; no join lock held).
  if (result.foundDependencyInfo) {
    cache.recordDependency(importInfo.importIdentifier,
                           *result.foundDependencyInfo);
    if (!result.incompatibleCandidates.empty()) {
      std::string name = importInfo.importIdentifier;
      auto candidates = result.incompatibleCandidates;
      deferDiagnostic(name, [this, name, candidates]() {
        scanner.ScanDiagnosticReporter.warnOnIncompatibleCandidates(name,
                                                                    candidates);
      });
    }
  } else if (!cache.findSwiftDependency(importInfo.importIdentifier)) {
    // Not a Swift module (and not recorded by a concurrent pre-roll). Record
    // the negative result so it is subsequently treated as a Clang import
    // candidate, and defer the only-incompatible-candidates diagnosis to
    // quiescence (where it runs single-threaded).
    cache.recordFailedSwiftDependencyLookup(importInfo.importIdentifier);
    ScannerImportStatementInfo info = importInfo;
    auto candidates = result.incompatibleCandidates;
    deferDiagnostic(info.importIdentifier, [this, info, candidates]() {
      scanner.ScanDiagnosticReporter.diagnoseFailureOnOnlyIncompatibleCandidates(
          info, candidates, cache, std::nullopt);
    });
  }

  // Step 2: notify the modules waiting on this import name, both as a Swift
  // import and as a Swift overlay (the two joins are independent; their locks
  // are taken one at a time, never nested).
  auto toFinalizeImports = collectFinalizedWaiters(
      swiftJoinMu, swiftJoins, swiftWaiters, importInfo.importIdentifier);
  auto toFinalizeOverlays = collectFinalizedWaiters(
      overlayJoinMu, overlayJoins, overlayWaiters, importInfo.importIdentifier);

  for (const auto &moduleID : toFinalizeImports)
    finalizeSwiftImports(moduleID);
  for (const auto &moduleID : toFinalizeOverlays)
    finalizeOverlay(moduleID);
}

ModuleDependencyIDSetVector ScanWorkState::collectResolvedSwiftDependencies(
    const ModuleDependencyID &moduleID) {
  auto moduleInfo = cache.getDependencyInfo(moduleID);
  ModuleDependencyIDSetVector swiftDependencies;
  auto consider = [&](const ScannerImportStatementInfo &importInfo) {
    if (moduleID.ModuleName == importInfo.importIdentifier)
      return;
    if (auto kind = cache.findSwiftDependencyKind(importInfo.importIdentifier))
      swiftDependencies.insert({importInfo.importIdentifier, *kind});
  };
  for (const auto &importInfo : moduleInfo.getModuleImports())
    consider(importInfo);
  for (const auto &importInfo : moduleInfo.getOptionalModuleImports())
    consider(importInfo);
  return swiftDependencies;
}

void ScanWorkState::finalizeSwiftImports(const ModuleDependencyID &moduleID) {
  auto swiftDependencies = collectResolvedSwiftDependencies(moduleID);
  cache.setImportedSwiftDependencies(moduleID, swiftDependencies.getArrayRef());

  // Expand the dataflow: resolve each newly-discovered Swift import's imports.
  for (const auto &dep : swiftDependencies)
    submitSwift(dep);

  // Begin resolving this module's Clang module dependencies now that its Swift
  // imports are known.
  startClangJoin(moduleID);
}

// MARK: Clang resolution

StringRef
ScanWorkState::canonicalClangImportName(StringRef importIdentifier) const {
  if (importIdentifier == scanner.ScanASTContext.Id_CxxStdlib.str())
    return "std";
  return importIdentifier;
}

void ScanWorkState::forEachUnresolvedClangImport(
    const ModuleDependencyInfo &moduleInfo,
    llvm::function_ref<void(StringRef, const ScannerImportStatementInfo &, bool)>
        fn) {
  // Imports already resolved to a Swift module are not Clang imports.
  llvm::StringSet<> resolvedSwiftNames;
  for (const auto &dep : moduleInfo.getImportedSwiftDependencies())
    resolvedSwiftNames.insert(dep.ModuleName);

  auto visit = [&](const ScannerImportStatementInfo &importInfo,
                   bool isRequired) {
    if (resolvedSwiftNames.contains(importInfo.importIdentifier))
      return;
    StringRef canonicalName =
        canonicalClangImportName(importInfo.importIdentifier);
    if (canonicalName == importInfo.importIdentifier) {
      fn(canonicalName, importInfo, isRequired);
    } else {
      // Canonicalized (e.g. CxxStdlib -> std): rebuild the import under the
      // canonical name so a query or diagnosis uses the right module name.
      ScannerImportStatementInfo canonicalImport(
          canonicalName.str(), importInfo.isExported, importInfo.accessLevel,
          importInfo.importLocations);
      fn(canonicalName, canonicalImport, isRequired);
    }
  };
  for (const auto &importInfo : moduleInfo.getModuleImports())
    visit(importInfo, /*isRequired=*/true);
  for (const auto &importInfo : moduleInfo.getOptionalModuleImports())
    visit(importInfo, /*isRequired=*/false);
}

void ScanWorkState::startClangJoin(const ModuleDependencyID &moduleID) {
  auto moduleInfo = cache.getDependencyInfo(moduleID);

  // If this module's Clang dependencies are already fully resolved (a prior
  // scan or re-entry computed them), its Clang sub-graph is complete; nothing
  // to scan. The post-drain module-set reconstruction recovers its reachable
  // Clang modules.
  if (!moduleInfo.getImportedClangDependencies().empty())
    return;

  // Gather the distinct unresolved-as-Clang import names in import order. An
  // import that appears as both required and optional is treated as required
  // for failure purposes.
  struct GatheredImport {
    ScannerImportStatementInfo importInfo;
    bool isRequired;
  };
  llvm::StringMap<GatheredImport> gathered;
  llvm::SmallVector<std::string, 8> gatherOrder;
  forEachUnresolvedClangImport(
      moduleInfo, [&](StringRef canonicalName,
                      const ScannerImportStatementInfo &canonicalImport,
                      bool isRequired) {
        auto it = gathered.find(canonicalName);
        if (it == gathered.end()) {
          gathered.insert({canonicalName, {canonicalImport, isRequired}});
          gatherOrder.push_back(canonicalName.str());
        } else if (isRequired) {
          it->second.isRequired = true;
        }
      });

  // Register the module's join: skip any already-cached Clang imports (they are
  // re-derived from the cache at finalization), register a waiter for each
  // remaining name, and dispatch its scan.
  llvm::SmallVector<std::string, 8> toSubmit;
  bool finalizeNow = false;
  {
    std::lock_guard<std::mutex> guard(joinMu);
    auto &join = clangJoins[moduleID];
    for (const auto &canonicalName : gatherOrder) {
      const auto &gatheredImport = gathered.find(canonicalName)->second;
      if (cache.hasClangDependency(canonicalName) &&
          cache.hasVisibleClangModulesFromLookup(canonicalName))
        continue;
      clangWaiters[canonicalName].push_back(
          {moduleID, gatheredImport.importInfo, gatheredImport.isRequired});
      ++join.pending;
      toSubmit.push_back(canonicalName);
    }
    if (join.pending == 0) {
      join.finalized = true;
      finalizeNow = true;
    }
  }

  for (const auto &canonicalName : toSubmit)
    submitClangIfNeeded(canonicalName);

  if (finalizeNow)
    finalizeClangJoin(moduleID);
}

void ScanWorkState::submitClangIfNeeded(StringRef clangName) {
  {
    std::lock_guard<std::mutex> guard(pendingMu);
    if (!submittedClang.insert(clangName).second)
      return;
  }
  std::string name = clangName.str();
  enqueue([this, name]() { runClangModuleTask(name); });
}

void ScanWorkState::runClangModuleTask(std::string clangName) {
  auto scanResult = scanner.scanClangModuleByNameOnWorker(
      scanner.getModuleImportIdentifier(clangName));

  // Step 1: record the scan result into the cache. Done before taking joinMu;
  // the cache lock is never acquired while joinMu is held except as the
  // innermost lock in the retry sweep below.
  if (scanResult) {
    cache.recordClangDependencies(
        scanResult->ModuleGraph, scanner.ScanASTContext.Diags,
        [this](const clang::tooling::dependencies::ModuleDeps &clangDep) {
          return scanner.bridgeClangModuleDependency(clangDep);
        });
    cache.setVisibleClangModulesFromLookup(
        {clangName, ModuleDependencyKind::Clang}, scanResult->VisibleModules);
    scanner.ScanDiagnosticReporter.registerNamedClangDependency();
  }

  // Step 2: resolve the modules waiting on this Clang name, then sweep the
  // retry list against the now-augmented cache.
  std::vector<ModuleDependencyID> finalized;
  {
    std::lock_guard<std::mutex> guard(joinMu);
    bool resolved = cache.hasClangDependency(clangName) &&
                    cache.hasVisibleClangModulesFromLookup(clangName);

    auto collectIfDone = [&](const ModuleDependencyID &requestor, Join &join) {
      if (join.pending == 0 && !join.finalized) {
        join.finalized = true;
        finalized.push_back(requestor);
      }
    };

    auto waitersIt = clangWaiters.find(clangName);
    if (waitersIt != clangWaiters.end()) {
      for (const auto &waiter : waitersIt->second) {
        auto &join = clangJoins[waiter.requestor];
        if (resolved) {
          --join.pending;
          collectIfDone(waiter.requestor, join);
        } else if (waiter.isRequired) {
          // A genuine-looking failure: retry against the cache as sibling
          // scans record transitive modules; diagnosed at quiescence if it
          // never resolves. Pending is not decremented until it resolves.
          pendingRetries.push_back({waiter.requestor, waiter.importInfo});
        } else {
          // An optional-only import that failed is dropped silently.
          --join.pending;
          collectIfDone(waiter.requestor, join);
        }
      }
      clangWaiters.erase(waitersIt);
    }

    // Sweep: a sibling's transitive record may have satisfied an earlier
    // failure. A record that completes after this read triggers its own sweep.
    sweepPendingRetries_locked(collectIfDone);
  }

  for (const auto &moduleID : finalized)
    finalizeClangJoin(moduleID);
}

void ScanWorkState::sweepPendingRetries_locked(
    llvm::function_ref<void(const ModuleDependencyID &, Join &)> onResolved) {
  for (auto it = pendingRetries.begin(); it != pendingRetries.end();) {
    auto &join = clangJoins[it->first];
    auto retryModuleID = ModuleDependencyID{it->second.importIdentifier,
                                            ModuleDependencyKind::Clang};
    if (!join.finalized && cache.findDependency(retryModuleID)) {
      // Synthesize a by-name visible-modules entry for the transitively
      // discovered module so it is recovered by `collectResolvedClang...`.
      cache.setVisibleClangModulesFromLookup(
          retryModuleID, {it->second.importIdentifier});
      scanner.ScanDiagnosticReporter.registerNamedClangDependency();
      --join.pending;
      onResolved(it->first, join);
      it = pendingRetries.erase(it);
    } else {
      ++it;
    }
  }
}

void ScanWorkState::finalizeClangJoin(const ModuleDependencyID &moduleID) {
  // Re-derive the resolved Clang dependencies from the cache in import order.
  auto clangDependencies = collectResolvedClangDependencies(moduleID);
  // Preserve the phase-based "empty => no write" semantics: a module with no
  // resolved Clang dependencies leaves its recorded state unchanged.
  if (!clangDependencies.empty())
    cache.setImportedClangDependencies(moduleID,
                                       clangDependencies.getArrayRef());

  // Advance the module: a header-bearing module begins its bridging/binary
  // header scan (whose completion fires its overlay queries); a header-less
  // module begins its overlay queries immediately.
  if (!submitHeaderScan(moduleID))
    submitOverlayQueries(moduleID);
}

ModuleDependencyIDSetVector ScanWorkState::collectResolvedClangDependencies(
    const ModuleDependencyID &moduleID) {
  auto moduleInfo = cache.getDependencyInfo(moduleID);
  ModuleDependencyIDSetVector clangDependencies;
  llvm::StringSet<> seen;
  forEachUnresolvedClangImport(
      moduleInfo,
      [&](StringRef canonicalName, const ScannerImportStatementInfo &, bool) {
        if (!seen.insert(canonicalName).second)
          return;
        if (cache.hasClangDependency(canonicalName) &&
            cache.hasVisibleClangModulesFromLookup(canonicalName))
          clangDependencies.insert(
              {canonicalName.str(), ModuleDependencyKind::Clang});
      });
  return clangDependencies;
}

// MARK: Bridging-header resolution

bool ScanWorkState::submitHeaderScan(const ModuleDependencyID &moduleID) {
  auto moduleInfo = cache.getDependencyInfo(moduleID);

  // Already scanned (e.g. a re-entry of an already-resolved module): skip.
  if (!moduleInfo.getHeaderClangDependencies().empty())
    return false;

  // Only modules with a textual bridging header or a binary header input have
  // header dependencies to scan (matching `resolveHeaderDependenciesForModule`).
  bool isTextualModuleWithBridgingHeader =
      moduleInfo.isTextualSwiftModule() &&
      moduleInfo.getBridgingHeader().has_value();
  bool isBinaryModuleWithHeaderInput =
      moduleInfo.isSwiftBinaryModule() &&
      !moduleInfo.getAsSwiftBinaryModule()->headerImport.empty();
  if (!isTextualModuleWithBridgingHeader && !isBinaryModuleWithHeaderInput)
    return false;

  {
    std::lock_guard<std::mutex> guard(pendingMu);
    if (!submittedHeader.insert(moduleID.ModuleName).second)
      return false;
  }
  ModuleDependencyID id = moduleID;
  enqueue([this, id]() {
    ModuleDependencyIDSetVector headerClangModuleDependencies;
    scanner.resolveHeaderDependenciesForModule(id,
                                               headerClangModuleDependencies);
    // The module's full set of visible Clang modules (direct imports plus
    // header-visible) is now known, so its Swift-overlay queries can begin.
    submitOverlayQueries(id);
  });
  return true;
}

// MARK: Swift-overlay resolution

std::vector<std::string>
ScanWorkState::gatherOverlayCandidates(const ModuleDependencyID &moduleID) {
  std::vector<std::string> candidates;
  auto visibleClangDependencies = cache.getAllVisibleClangModules(moduleID);
  for (const auto &clangDep : visibleClangDependencies) {
    // Avoid the Swift-overlay lookup for the underlying Clang module of this
    // same Swift module.
    if (clangDep.getKey() == moduleID.ModuleName)
      continue;
    candidates.push_back(clangDep.getKey().str());
  }

  // C++ interop: if any visible Clang dependency is a (split) C++ standard
  // library module, the CxxStdlib overlay must be queried explicitly.
  bool lookupCxxStdLibOverlay =
      scanner.ScanCompilerInvocation.getLangOptions().EnableCXXInterop;
  if (lookupCxxStdLibOverlay &&
      moduleID.Kind == ModuleDependencyKind::SwiftInterface) {
    auto moduleInfo = cache.getDependencyInfo(moduleID);
    const auto commandLine = moduleInfo.getCommandline();
    if (llvm::find(commandLine, "-formal-cxx-interoperability-mode=off") !=
        commandLine.end())
      lookupCxxStdLibOverlay = false;
  } else if (lookupCxxStdLibOverlay &&
             moduleID.Kind == ModuleDependencyKind::SwiftBinary) {
    auto moduleInfo = cache.getDependencyInfo(moduleID);
    if (!moduleInfo.getAsSwiftBinaryModule()->isBuiltWithCxxInterop)
      lookupCxxStdLibOverlay = false;
  }
  // FIXME: We always treat 'Darwin' as built without C++ interop, matching the
  // phase-based scanner.
  if (lookupCxxStdLibOverlay && moduleID.ModuleName == "Darwin")
    lookupCxxStdLibOverlay = false;

  if (lookupCxxStdLibOverlay) {
    for (const auto &clangDep : visibleClangDependencies) {
      auto clangDepName = clangDep.getKey();
      // Read just the IsSystem bit by value (nullopt if this is not a recorded
      // Clang module) rather than cloning the module's whole dependency info.
      auto isSystem = cache.isClangModuleSystem(clangDepName);
      if (isSystem && importer::isCxxStdModule(clangDepName, *isSystem)) {
        candidates.push_back(scanner.ScanASTContext.Id_CxxStdlib.str().str());
        break;
      }
    }
  }

  return candidates;
}

void ScanWorkState::submitOverlayQueries(const ModuleDependencyID &moduleID) {
  {
    std::lock_guard<std::mutex> guard(pendingMu);
    if (!submittedOverlay.insert(moduleID.ModuleName).second)
      return;
  }

  auto candidates = gatherOverlayCandidates(moduleID);

  llvm::SmallVector<std::string, 8> toScan;
  bool finalizeNow = false;
  {
    std::lock_guard<std::mutex> guard(overlayJoinMu);
    // Stash the candidates so finalizeOverlay re-derives the recorded overlays
    // from the same set that drove the queries, without recomputing it.
    overlayCandidates[moduleID] = candidates;
    auto &join = overlayJoins[moduleID];
    for (const auto &candidate : candidates) {
      if (cache.hasQueriedSwiftDependency(candidate))
        continue; // resolved inline; derived from the cache at finalization
      overlayWaiters[candidate].push_back(moduleID);
      ++join.pending;
      toScan.push_back(candidate);
    }
    if (join.pending == 0) {
      join.finalized = true;
      finalizeNow = true;
    }
  }

  for (const auto &candidate : toScan)
    submitSwiftImportIfNeeded(ScannerImportStatementInfo(candidate),
                              /*isTestableImport=*/false);

  if (finalizeNow)
    finalizeOverlay(moduleID);
}

ModuleDependencyIDSetVector ScanWorkState::collectResolvedOverlayDependencies(
    const ModuleDependencyID &moduleID) {
  // Read the candidate set stashed when the queries were dispatched, so the
  // recorded overlays come from the same set (no recomputation, no drift).
  std::vector<std::string> candidates;
  {
    std::lock_guard<std::mutex> guard(overlayJoinMu);
    auto it = overlayCandidates.find(moduleID);
    if (it != overlayCandidates.end())
      candidates = it->second;
  }

  ModuleDependencyIDSetVector overlayDependencies;
  for (const auto &candidate : candidates) {
    if (candidate == moduleID.ModuleName)
      continue;
    if (auto kind = cache.findSwiftDependencyKind(candidate))
      overlayDependencies.insert({candidate, *kind});
  }
  return overlayDependencies;
}

void ScanWorkState::finalizeOverlay(const ModuleDependencyID &moduleID) {
  auto overlayDependencies = collectResolvedOverlayDependencies(moduleID);
  cache.setSwiftOverlayDependencies(moduleID,
                                    overlayDependencies.getArrayRef());

  // Expand each discovered overlay through the dataflow, replacing the
  // synthetic `_<Main>-OverlayDependencies` recursion: an overlay's own
  // imports, Clang dependencies, headers, and overlays resolve naturally.
  for (const auto &overlay : overlayDependencies)
    submitSwift(overlay);
}

// MARK: Driver

bool ScanWorkState::finalizeQuiescent() {
  // One round of post-drain finalization. The driver calls this each time the
  // dataflow drains; finalizing the modules that were blocked on genuine Clang
  // failures advances them (header/overlay scans and their cascades), which can
  // enqueue more work, so a round that finalizes anything returns true and the
  // driver waits and calls again. Diagnosis and the deferred-diagnostic flush
  // happen only on the final round, once no joins remain to finalize.
  std::vector<ModuleDependencyID> finalized;
  {
    std::lock_guard<std::mutex> guard(joinMu);
    // Retry sweep against the now-complete cache. The loop below finalizes
    // every still-pending join, so the sweep needs no per-resolution callback.
    sweepPendingRetries_locked([](const ModuleDependencyID &, Join &) {});

    // Finalize every module whose join has not yet been finalized (those
    // blocked on genuine failures, or brought to zero by the sweep above).
    for (auto &entry : clangJoins) {
      if (!entry.second.finalized) {
        entry.second.finalized = true;
        finalized.push_back(entry.first);
      }
    }
  }

  // Advancing these modules (header/overlay scans and their cascades) enqueues
  // new dataflow work; defer diagnosis until the driver waits for it to drain
  // and calls back.
  for (const auto &moduleID : finalized)
    finalizeClangJoin(moduleID);
  if (!finalized.empty())
    return true;

  // Truly quiescent: no joins left to finalize, nothing enqueued. Diagnose
  // genuine failures and flush the buffered diagnostics, exactly once.
  std::vector<ModuleIDImportInfoPair> genuineFailures;
  {
    std::lock_guard<std::mutex> guard(joinMu);
    genuineFailures.assign(pendingRetries.begin(), pendingRetries.end());
    pendingRetries.clear();
  }

  // Flush the buffered Swift-side diagnostics in deterministic order first
  // (these mirror Phase-1 diagnoses), then diagnose genuine Clang failures.
  // `ReportedMissing` de-duplication ensures each missing module is reported
  // once across the two sources.
  llvm::stable_sort(deferredDiagnostics, [](const auto &lhs, const auto &rhs) {
    return lhs.first < rhs.first;
  });
  for (auto &deferred : deferredDiagnostics)
    deferred.second();
  deferredDiagnostics.clear();

  llvm::stable_sort(genuineFailures, [](const ModuleIDImportInfoPair &lhs,
                                        const ModuleIDImportInfoPair &rhs) {
    if (lhs.first.ModuleName != rhs.first.ModuleName)
      return lhs.first.ModuleName < rhs.first.ModuleName;
    return lhs.second.importIdentifier < rhs.second.importIdentifier;
  });
  for (const auto &failure : genuineFailures) {
    // The pool is idle here, so the worker checkout in
    // `attemptToFindResolvingSerializedSearchPath` is safe.
    scanner.ScanDiagnosticReporter.diagnoseModuleNotFoundFailure(
        failure.second, cache, failure.first,
        scanner.attemptToFindResolvingSerializedSearchPath(failure.second));
  }

  return false;
}

bool ScanWorkState::awaitAll() {
  // Block until the dataflow drains, then run one finalization round. A round
  // that finalizes modules blocked on genuine failures enqueues more work
  // (their header/overlay scans and cascades); loop until a round adds nothing.
  while (true) {
    pool.wait(taskGroup);
    if (!finalizeQuiescent())
      break;
  }
  return anyError.load(std::memory_order_acquire);
}
