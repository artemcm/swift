// Single-root lowering: with -sil-on-demand-emission, -sil-on-demand-root
// seeds one function instead of every function in the file. That function,
// its closures, and its local functions are lowered; the other functions it
// references stay external declarations.

// RUN: %empty-directory(%t)
// RUN: split-file %s %t

// The root, by name.
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   -sil-verify-all -Xllvm -sil-on-demand-emission \
// RUN:   -Xllvm -sil-on-demand-root=root %t/Root.swift -o %t/byname.sil
// RUN: %FileCheck --check-prefix=ROOT %s < %t/byname.sil
// RUN: %FileCheck --check-prefix=ROOTBODY %s < %t/byname.sil
// RUN: %FileCheck --check-prefix=NOTEMITTED %s < %t/byname.sil

// The same root, by a position inside its body (a local function there).
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   -sil-verify-all -Xllvm -sil-on-demand-emission \
// RUN:   -Xllvm -sil-on-demand-root=5:3 %t/Root.swift -o %t/byline.sil
// RUN: diff %t/byname.sil %t/byline.sil

// A method, by a line in its body.
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   -sil-verify-all -Xllvm -sil-on-demand-emission \
// RUN:   -Xllvm -sil-on-demand-root=12 %t/Root.swift -o %t/method.sil
// RUN: %FileCheck --check-prefix=METHOD %s < %t/method.sil
// RUN: %FileCheck --check-prefix=METHODNOT %s < %t/method.sil

// No function by that name.
// RUN: not %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   -Xllvm -sil-on-demand-emission -Xllvm -sil-on-demand-root=nope \
// RUN:   %t/Root.swift -o /dev/null 2>&1 | %FileCheck --check-prefix=UNKNOWN %s

// No function at that line.
// RUN: not %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   -Xllvm -sil-on-demand-emission -Xllvm -sil-on-demand-root=200 \
// RUN:   %t/Root.swift -o /dev/null 2>&1 | %FileCheck --check-prefix=NOLINE %s

// The legacy path ignores the flag.
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   %t/Root.swift -o %t/legacy.sil
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   -Xllvm -sil-on-demand-root=root %t/Root.swift -o %t/legacy-root.sil
// RUN: diff %t/legacy.sil %t/legacy-root.sil

// ROOT-DAG: sil hidden {{.*}}@$s1M4rootySiSaySiGF : {{.*}} {
// ROOT-DAG: sil private {{.*}}@$s1M4rootySiSaySiGFS2icfU_ : {{.*}} {
// ROOT-DAG: sil private {{.*}}@$s1M4rootySiSaySiGF5localL_yS2iF : {{.*}} {
// ROOT-DAG: sil hidden_external @$s1M6helperyS2iF :

// The @_transparent callee is inlined into the root.
// ROOTBODY-LABEL: sil hidden {{.*}}@$s1M4rootySiSaySiGF : {{.*}} {
// ROOTBODY-NOT: function_ref @$s1M7inlinedyS2iF
// ROOTBODY: } // end sil function '$s1M4rootySiSaySiGF'

// Functions the root doesn't reach aren't in the module at all. The output
// also leaves out the module's Swift declarations, which printing would
// otherwise type-check, signature by signature, for the whole file.
// NOTEMITTED-NOT: @$s1M5otherSiyF
// NOTEMITTED-NOT: @$s1M1SV6methodSiyF
// NOTEMITTED-NOT: {{^}}func {{.*}}(
// NOTEMITTED-NOT: {{^}}struct S

// METHOD-DAG: sil hidden {{.*}}@$s1M1SV6methodSiyF : {{.*}} {
// METHOD-DAG: sil hidden_external @$s1M5otherSiyF :
// METHODNOT-NOT: @$s1M4rootySiSaySiGF : {{.*}} {

// UNKNOWN: error: invalid value 'nope' in '-sil-on-demand-root'
// NOLINE: error: invalid value '200' in '-sil-on-demand-root'

//--- Root.swift
func helper(_ x: Int) -> Int { return x + 1 }
@_transparent func inlined(_ x: Int) -> Int { return x * 2 }
func root(_ xs: [Int]) -> Int {
  let f = { (y: Int) -> Int in y + helper(y) }
  func local(_ z: Int) -> Int { return z - 1 }
  return f(xs.count) + inlined(local(1))
}
func other() -> Int { return 42 }
struct S {
  var v: Int
  func method() -> Int {
    return other() + v
  }
}
