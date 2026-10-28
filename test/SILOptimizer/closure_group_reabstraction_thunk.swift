// RUN: %target-swift-frontend -emit-sil %s -module-name M -sil-verify-all -o - | %FileCheck %s
// RUN: %target-swift-frontend -emit-sil %s -module-name M -o /dev/null -Xllvm -sil-print-closure-groups 2>&1 | %FileCheck %s --check-prefix=GROUPS

// test() captures its box in a closure, then reabstracts the closure with a
// partial_apply of a reabstraction thunk. No closure link reaches a thunk. The
// partial_apply passes the thunk a closure, not a box or an address, so it isn't
// a capture edge, and it isn't a call. So the thunk is a closure group of its
// own, after test()'s. When MandatoryAllocBoxToStack runs on test()'s group, it follows
// the closure into the thunk, which no pass of the block has run on yet. The
// block's passes leave such a thunk unchanged, so the walk reads the same uses
// as when they had run on it first. The box stays a box, because the
// reabstracted closure escapes.

// GROUPS: Closure group for mandatory-allocbox-to-stack: $s1M4testyyF $s1M4testyyFSiycfU_{{$}}
// GROUPS: Closure group for mandatory-allocbox-to-stack: $sSiIegd_SiIegr_TR{{$}}

func takesGeneric<T>(_ f: @escaping () -> T) {}

// CHECK-LABEL: sil hidden @$s1M4testyyF : $@convention(thin) () -> () {
// CHECK:         alloc_box ${ var Int }, var, name "x"
// CHECK:         [[THUNK:%.*]] = function_ref @$sSiIegd_SiIegr_TR
// CHECK:         partial_apply [callee_guaranteed] [[THUNK]](
// CHECK-LABEL: } // end sil function '$s1M4testyyF'
func test() {
  var x = 0
  let f: () -> Int = { x += 1; return x }
  takesGeneric(f)
}
