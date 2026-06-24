//===--- ScanWorkState.h - Continuation-style scan scheduler ----*- C++ -*-===//
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
//
// This file defines ScanWorkState, which drives the transitive-closure
// dependency scan as a continuation dataflow: the completion of each scan task
// fires the tasks it unblocks, rather than waiting at a phase boundary.
//
//===----------------------------------------------------------------------===//

#ifndef SWIFT_DEPENDENCYSCAN_SCANWORKSTATE_H
#define SWIFT_DEPENDENCYSCAN_SCANWORKSTATE_H

#include "swift/AST/Identifier.h"
#include "swift/AST/ModuleDependencies.h"
#include "swift/DependencyScan/ModuleDependencyScanner.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/STLFunctionalExtras.h"
#include "llvm/ADT/StringMap.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/ADT/StringSet.h"
#include "llvm/Support/ThreadPool.h"
#include <atomic>
#include <functional>
#include <mutex>
#include <unordered_map>
#include <utility>
#include <vector>

namespace swift {

/// Drives the transitive-closure dependency scan as a continuation dataflow.
/// The moment a Swift module's scan discovers a new import, the task that
/// resolves it is dispatched immediately, concurrently with every other
/// in-flight scan, rather than waiting for a phase barrier. The single block
/// point is \c awaitAll, on the main thread, until the dataflow drains.
///
/// Swift discovery, Clang resolution, bridging-header scans, and Swift-overlay
/// resolution all run as the dataflow, dissolving the phase scanner's three
/// \c pool.wait() barriers and its synthetic-module overlay recursion.
///
/// Each Swift module passes through three symmetric per-module counted joins,
/// in order, each finalized exactly once when its last dependency resolves:
///   - The Swift-import join: each distinct imported module *name* is scanned
///     at most once across the whole scan (preserving the phase scanner's
///     single-query-per-name guarantee); a Swift module is "Swift-complete"
///     once every one of its imports has resolved, at which point its resolved
///     Swift dependencies are recorded and its Clang resolution begins.
///   - The Clang join: \c setImportedClangDependencies aggregates across all of
///     a module's Clang imports, so it is written once the last of those
///     imports resolves; this then fires the module's header scan (if any) and,
///     on its completion, the module's overlay queries.
///   - The Swift-overlay join: each Clang module visible to the Swift module is
///     queried for a Swift overlay; once all such queries resolve, the overlays
///     are recorded and each discovered overlay is expanded through the
///     dataflow, in place of the phase scanner's synthetic
///     \c _<Main>-OverlayDependencies recursion.
///
/// All recording into \c ModuleDependenciesCache happens from worker threads,
/// concurrently; the cache is internally synchronized (see
/// \c ModuleDependenciesCache::CacheMutex). This object owns the in-flight
/// dedup gates, the three joins, the incremental failed-Clang-import retry, the
/// deferred-diagnostic buffer, and the thread-pool task group whose draining
/// defines quiescence. It is stack-local to
/// \c ModuleDependencyScanner::resolveImportedModuleDependencies and holds
/// references (not copies) to the scanner, cache, and thread pool, all of which
/// outlive it by stack ordering.
class ScanWorkState {
public:
  ScanWorkState(ModuleDependencyScanner &scanner,
                ModuleDependenciesCache &cache, llvm::ThreadPoolInterface &pool);

  /// Seed the dataflow with a Swift (interface, binary, or source) root module
  /// whose dependency info is already recorded in the cache.
  void submitSwift(const ModuleDependencyID &moduleID);

  /// Block until the dataflow reaches quiescence (no scans in flight and no
  /// finalization work pending). Returns true if any task reported an error.
  bool awaitAll();

private:
  /// A Swift module \p moduleID awaiting resolution of one of its imports as a
  /// Clang module \c C (the key in \c clangWaiters).
  struct ClangWaiter {
    ModuleDependencyID requestor;
    /// The (possibly \c CxxStdlib->std canonicalized) import statement, used to
    /// diagnose a genuine resolution failure.
    ScannerImportStatementInfo importInfo;
    /// Whether \p requestor imports \c C as a required (non-optional) import.
    /// A failed optional-only import is dropped silently, matching the
    /// phase-based scanner.
    bool isRequired;
  };

  /// A counted join: a module awaits resolution of \c pending imports, and is
  /// finalized exactly once when that count reaches zero.
  struct Join {
    size_t pending = 0;
    bool finalized = false;
  };

  /// Per-module counted joins (Swift-import, Swift-overlay, Clang).
  using JoinMap = std::unordered_map<ModuleDependencyID, Join>;
  /// Module names mapped to the modules whose join awaits that name (Swift
  /// import and overlay joins; the Clang join uses \c ClangWaiter instead).
  using WaiterMap = llvm::StringMap<std::vector<ModuleDependencyID>>;

  /// Resolve \p name against a join: under \p mu, decrement every waiter's
  /// \c pending in \p joins, erase the waiter list from \p waiters, and return
  /// the modules whose join reached zero (to be finalized after the lock is
  /// released). Shared by the Swift-import and Swift-overlay joins.
  llvm::SmallVector<ModuleDependencyID, 4>
  collectFinalizedWaiters(std::mutex &mu, JoinMap &joins, WaiterMap &waiters,
                          StringRef name);

  // ---- Swift import resolution ------------------------------------------

  /// Begin resolving \p moduleID's imports: register it with the Swift-import
  /// join and dispatch a by-name scan for each of its not-yet-queried imports.
  void startSwiftImportJoin(ModuleDependencyID moduleID);

  /// Dispatch a by-name Swift scan of \p importInfo's module unless one was
  /// already dispatched for that name in this scan.
  void submitSwiftImportIfNeeded(const ScannerImportStatementInfo &importInfo,
                                 bool isTestableImport);

  /// The by-name Swift scan task body: scan \p importName, record its result
  /// (or failure) into the cache, then notify every Swift module waiting on it.
  void runSwiftImportTask(ScannerImportStatementInfo importInfo,
                          bool isTestableImport);

  /// A Swift module's imports have all resolved: record its directly-imported
  /// Swift dependencies, expand each of them, and begin its Clang join.
  void finalizeSwiftImports(const ModuleDependencyID &moduleID);

  // ---- Clang resolution -------------------------------------------------

  /// The canonical Clang module name a by-name import resolves against: a
  /// `CxxStdlib` import is queried as the Clang module `std`; any other import
  /// keeps its own name. Single definition of the canonicalization rule, shared
  /// by the Clang-join gather and the resolved-edge re-derivation.
  StringRef canonicalClangImportName(StringRef importIdentifier) const;

  /// Visit each of \p moduleInfo's imports that is not resolved as a Swift
  /// module, in required-then-optional order, passing its canonical Clang name
  /// (\c canonicalClangImportName), the (correspondingly canonicalized) import,
  /// and whether the import is required. Drives both the Clang-join queries
  /// (\c startClangJoin) and the recorded-edge re-derivation
  /// (\c collectResolvedClangDependencies), so the two stay in lockstep.
  void forEachUnresolvedClangImport(
      const ModuleDependencyInfo &moduleInfo,
      llvm::function_ref<void(StringRef canonicalName,
                              const ScannerImportStatementInfo &canonicalImport,
                              bool isRequired)>
          fn);

  /// Compute \p moduleID's unresolved-as-Clang imports and register it with the
  /// Clang join, dispatching a Clang scan for each distinct unresolved name.
  void startClangJoin(const ModuleDependencyID &moduleID);

  /// Dispatch a Clang-module scan for \p clangName unless one was already
  /// dispatched for it in this scan.
  void submitClangIfNeeded(StringRef clangName);

  /// The Clang-module scan task body: scan \p clangName, record its result
  /// into the cache, then resolve every Swift module waiting on it (draining
  /// the incremental retry list against the augmented cache).
  void runClangModuleTask(std::string clangName);

  /// Sweep the incremental retry list against the now-augmented cache: a
  /// sibling Clang scan's transitive record may have satisfied a required
  /// import that earlier looked like a genuine failure. For each retry whose
  /// module now resolves, synthesize its by-name visible-modules entry,
  /// decrement its requestor's join \c pending, invoke \p onResolved, and drop
  /// it from the list. Requestors whose join is already finalized are skipped
  /// (their failed imports stay failed). Caller must hold \c joinMu.
  void sweepPendingRetries_locked(
      llvm::function_ref<void(const ModuleDependencyID &, Join &)> onResolved);

  /// A module's Clang join is complete: commit its resolved Clang dependencies
  /// (re-derived from the cache in import order, so the output is deterministic
  /// and independent of scan-completion order), then advance it. A
  /// header-bearing module begins its bridging/binary-header scan, whose
  /// completion fires its overlay queries; a header-less module begins its
  /// overlay queries directly. The Clang-join counterpart of
  /// \c finalizeSwiftImports and \c finalizeOverlay.
  void finalizeClangJoin(const ModuleDependencyID &moduleID);

  // ---- Bridging-header resolution (Stage 2) -----------------------------

  /// Dispatch a bridging/binary-header scan for \p moduleID unless it has no
  /// header inputs, was already scanned, or one was already dispatched. Fired
  /// once a module's Clang join is finalized, so the header scan's
  /// already-seen-Clang-module snapshot includes the module's direct Clang
  /// dependencies. Returns true if a header scan was dispatched (in which case
  /// the overlay queries fire from the header scan's completion).
  bool submitHeaderScan(const ModuleDependencyID &moduleID);

  // ---- Swift-overlay resolution (Stage 3) -------------------------------

  /// Gather the Swift-overlay candidate module names for \p moduleID: the
  /// Clang modules visible to it (minus a self-overlay), plus the C++ standard
  /// library overlay when C++ interop requires it. Computed once per module in
  /// \c submitOverlayQueries and stashed in \c overlayCandidates, so the set
  /// that drives the queries is the same set re-derived at finalization.
  std::vector<std::string>
  gatherOverlayCandidates(const ModuleDependencyID &moduleID);

  /// Begin resolving \p moduleID's Swift overlays: for each overlay candidate,
  /// resolve the candidate's Swift module (via the shared by-name Swift scan),
  /// registering an overlay-join waiter for any not-yet-queried candidate.
  /// Fired once the module's Clang join (and header scan, if any) completes, so
  /// its full set of visible Clang modules is known.
  void submitOverlayQueries(const ModuleDependencyID &moduleID);

  /// A module's overlay candidates have all resolved: record its Swift-overlay
  /// dependencies and expand each discovered overlay through the dataflow
  /// (replacing the synthetic `_<Main>-OverlayDependencies` recursion).
  void finalizeOverlay(const ModuleDependencyID &moduleID);

  /// Re-derive \p moduleID's resolved Swift overlays: the stashed overlay
  /// candidates (\c overlayCandidates) that resolved to a Swift module, in
  /// candidate order.
  ModuleDependencyIDSetVector
  collectResolvedOverlayDependencies(const ModuleDependencyID &moduleID);

  // ---- Driver -----------------------------------------------------------

  /// Run once the dataflow has drained: a final retry sweep, diagnosis of
  /// genuine Clang-resolution failures, finalization of any remaining joins,
  /// and a deterministic flush of buffered diagnostics. Returns true if it
  /// enqueued new dataflow work (the header/overlay scans of modules that were
  /// blocked on genuine failures, and their cascades), in which case the driver
  /// waits for that work to drain and calls back.
  bool finalizeQuiescent();

  /// Dispatch \p work on the pool as part of \c taskGroup, so \c awaitAll can
  /// wait for the entire dataflow to drain. If a sibling task has already
  /// failed (\c anyError), the body is skipped.
  template <class Fn> void enqueue(Fn &&work);

  /// Buffer a per-event diagnostic for deterministic emission, in \p sortKey
  /// order, at quiescence (on the main thread).
  void deferDiagnostic(StringRef sortKey, std::function<void()> emit);

  /// Re-derive \p moduleID's resolved Swift dependencies from the cache, in
  /// import order (required imports first, then optional, de-duplicated).
  ModuleDependencyIDSetVector
  collectResolvedSwiftDependencies(const ModuleDependencyID &moduleID);

  /// Re-derive \p moduleID's resolved Clang dependencies from the cache, in
  /// import order (CxxStdlib canonicalized to std, de-duplicated), excluding
  /// imports resolved as Swift. Keeps the recorded order independent of
  /// scan-completion order.
  ModuleDependencyIDSetVector
  collectResolvedClangDependencies(const ModuleDependencyID &moduleID);

  ModuleDependencyScanner &scanner;
  ModuleDependenciesCache &cache;
  llvm::ThreadPoolInterface &pool;

  // In-flight dedup. Monotonic: a name is dispatched at most once per kind.
  // Distinct from the cache's committed-state gates, which a dispatched but
  // not-yet-recorded scan would not yet satisfy.
  std::mutex pendingMu;
  llvm::StringSet<> submittedSwiftModule; // module expansions started
  llvm::StringSet<> submittedSwiftImport; // by-name Swift scans dispatched
  llvm::StringSet<> submittedClang;       // by-name Clang scans dispatched
  llvm::StringSet<> submittedHeader;      // header scans dispatched
  llvm::StringSet<> submittedOverlay;     // overlay-query rounds dispatched

  // Per-module Swift-import join. Guarded by swiftJoinMu. The cache lock, when
  // needed here, is acquired under swiftJoinMu and released before it.
  std::mutex swiftJoinMu;
  JoinMap swiftJoins;
  WaiterMap swiftWaiters;

  // Per-module Swift-overlay join (Stage 3). Guarded by overlayJoinMu. The
  // overlay candidate set is computed once in submitOverlayQueries and stashed
  // here so finalizeOverlay re-derives the recorded overlays without recomputing
  // it (keeping the queried set and the recorded set identical by construction).
  std::mutex overlayJoinMu;
  JoinMap overlayJoins;
  WaiterMap overlayWaiters;
  std::unordered_map<ModuleDependencyID, std::vector<std::string>>
      overlayCandidates;

  // Per-module Clang-dependency join + incremental retry. All guarded by
  // joinMu. The cache lock, when needed here, is acquired under joinMu and
  // released before joinMu (joinMu -> cache lock order; never the reverse).
  std::mutex joinMu;
  JoinMap clangJoins;
  llvm::StringMap<std::vector<ClangWaiter>> clangWaiters;
  std::vector<ModuleIDImportInfoPair> pendingRetries;

  // Deterministic deferred diagnostics, flushed in sortKey order at quiescence.
  std::mutex deferredDiagMu;
  std::vector<std::pair<std::string, std::function<void()>>> deferredDiagnostics;

  // Error flag, set by the first failing task; subsequent task bodies skip.
  std::atomic<bool> anyError{false};

  // All dataflow tasks run in this group, so `awaitAll` can wait for the whole
  // scan to drain (and re-wait after each finalization round). Declared last so
  // its destructor (which drains the group) runs before the members its tasks
  // reference, keeping teardown safe on any early-exit path.
  llvm::ThreadPoolTaskGroup taskGroup;
};

} // namespace swift

#endif // SWIFT_DEPENDENCYSCAN_SCANWORKSTATE_H
