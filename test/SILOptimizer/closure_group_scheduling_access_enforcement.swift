// RUN: %target-swift-frontend -emit-sil %s -module-name E -sil-verify-all -o - | %FileCheck %s --check-prefix=SIL
// RUN: %target-swift-frontend -emit-sil %s -module-name E -Xllvm -sil-print-closure-groups -o /dev/null 2>&1 | %FileCheck %s --check-prefix=SETS
// RUN: %target-swift-frontend -emit-sil %s -module-name E -Xllvm -sil-print-after=access-enforcement-selection -Xllvm '-sil-print-function=$s1E7escapesSiyFyyXEfU0_' -o /dev/null 2>&1 | %FileCheck %s --check-prefix=PRINT

// AccessEnforcementSelection is a closure group transform. A parent records
// which of a closure's @inout_aliasable captures need dynamic enforcement before
// the closure is processed, so the closure must be in the parent's group.

@usableFromInline func modify(_ body: () -> ()) { body() }

var saved: (() -> Int)?

// x does not escape: the closure's access is static.
// SETS: Closure group for access-enforcement-selection: $s1E5localSiyF $s1E5localSiyFyyXEfU_{{$}}
// SIL-LABEL: sil private @$s1E5localSiyFyyXEfU_ : $@convention(thin) (@inout_aliasable Int) -> () {
// SIL: begin_access [modify] [static]
public func local() -> Int {
  var x = 0
  modify { x += 1 }
  return x
}

// x escapes before the non-escaping closure is used: its access is dynamic.
// The escaping closure captures the box, not the address, so it is a group by
// itself.
// SETS: Closure group for access-enforcement-selection: $s1E7escapesSiyF $s1E7escapesSiyFyyXEfU0_{{$}}
// SETS: Closure group for access-enforcement-selection: $s1E7escapesSiyFSiycfU_{{$}}
// SIL-LABEL: sil private @$s1E7escapesSiyFyyXEfU0_ : $@convention(thin) (@inout_aliasable Int) -> () {
// SIL: begin_access [modify] [dynamic]
public func escapes() -> Int {
  var x = 0
  saved = { x }
  modify { x += 1 }
  return x
}

// The dynamic capture travels through a middle closure, which forwards its own
// @inout_aliasable argument, to the inner closure.
// SETS: Closure group for access-enforcement-selection: $s1E6nestedSiyF $s1E6nestedSiyFyyXEfU0_ $s1E6nestedSiyFyyXEfU0_yyXEfU_{{$}}
// SIL-LABEL: sil private @$s1E6nestedSiyFyyXEfU0_yyXEfU_ : $@convention(thin) (@inout_aliasable Int) -> () {
// SIL: begin_access [modify] [dynamic]
public func nested() -> Int {
  var x = 0
  saved = { x }
  modify {
    modify { x += 1 }
  }
  return x
}

// -sil-print-after prints a member after the pass ran on its group.
// PRINT: sil private [ossa] @$s1E7escapesSiyFyyXEfU0_ : $@convention(thin) (@inout_aliasable Int) -> () {
// PRINT: begin_access [modify] [dynamic]

// SILGen emits a @backDeployed function's body twice, as the function and as
// its fallback, and both copies capture into the same closure. The closure
// joins them into one group.
// SETS: Closure group for access-enforcement-selection: $s1E12backDeployedSiyFTwB $s1E12backDeployedSiyFyyXEfU_ $s1E12backDeployedSiyF{{$}}
@available(macOS 10.15, *)
@backDeployed(before: macOS 99)
public func backDeployed() -> Int {
  var x = 0
  modify { x += 1 }
  return x
}
