// Test that the on-demand SILGen path matches the legacy path for
// @backDeployed functions. emitAbstractFuncDecl emits both the
// fallback (BackDeploymentKind::Fallback) and the dispatch thunk
// (BackDeploymentKind::Thunk) eagerly via emitFunctionDefinition.
// Phase 5's bootstrap sweep should pick both up.
//
// The thunk variant is what callers route through; the fallback is
// referenced from the thunk's body.

// RUN: %target-swift-emit-sil -parse-as-library -module-name back_deploy %s -target %target-cpu-apple-macosx10.50 > %t.normal.sil
// RUN: %target-swift-emit-sil -parse-as-library -module-name back_deploy -Xllvm -sil-on-demand-emission %s -target %target-cpu-apple-macosx10.50 > %t.ondemand.sil
// RUN: diff %t.normal.sil %t.ondemand.sil

// RUN: %target-swift-emit-sil -parse-as-library -module-name back_deploy %s -target %target-cpu-apple-macosx10.50 | %FileCheck %s

// REQUIRES: OS=macosx

// Fallback variant (suffix 'TwB') -- emitted first.
// CHECK-LABEL: sil shared @$s11back_deploy11trivialFuncyyFTwB

// Dispatch thunk (suffix 'Twb') -- emitted second, references the fallback.
// CHECK-LABEL: sil shared [back_deployed_thunk] @$s11back_deploy11trivialFuncyyFTwb

// Original definition of the back-deployed function -- emitted third.
// CHECK-LABEL: sil [available 10.52] @$s11back_deploy11trivialFuncyyF :
@backDeployed(before: macOS 10.52)
public func trivialFunc() {}

// A caller that forces the thunk variant to be referenced.
// CHECK-LABEL: sil hidden @$s11back_deploy6callerSiyF
func caller() -> Int {
  trivialFunc()
  return 0
}
