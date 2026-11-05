// Under -enable-lifetime-resolution, the SILGen pipeline runs
// MandatoryAllocBoxToStack, a module pass with no per-function equivalent for
// CleanedSILFunctionRequest to run (D3). On demand, the combination is
// rejected with a diagnostic instead of asserting in the pass manager.

// RUN: not %target-swift-frontend -emit-sil -Xllvm -sil-on-demand-emission \
// RUN:   -enable-lifetime-resolution %s -o /dev/null 2>&1 | %FileCheck %s

// The legacy path still compiles the same file.
// RUN: %target-swift-frontend -emit-sil -enable-lifetime-resolution %s \
// RUN:   -o /dev/null

// CHECK: error: unsupported argument combination: '-sil-on-demand-emission' and '-enable-lifetime-resolution'
// CHECK-NOT: Assertion

func f(_ x: Int) -> Int { var y = x; y += 1; return y }
