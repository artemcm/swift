// Phase 6.1 emitted the bodies of class methods on demand without the class's
// vtable, so the mandatory inliner couldn't devirtualize a call to a
// non-final stored property's accessor: the call stayed dynamic where legacy
// inlines the accessor. Phase 6.2 emits the vtable and the accessors, and the
// output equals legacy's. A final stored property is accessed directly on
// both paths.

// RUN: %empty-directory(%t)
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M %s \
// RUN:   -o %t/legacy.sil
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M %s \
// RUN:   -o %t/ondemand.sil -sil-verify-all -Xllvm -sil-on-demand-emission
// RUN: diff %t/legacy.sil %t/ondemand.sil
// RUN: %FileCheck %s < %t/ondemand.sil

final class Account {
  final var balance: Int = 0
  var owner: String
  init(owner: String) { self.owner = owner }

  // CHECK-LABEL: sil hidden @$s1M7AccountC7deposityySiFfA_ :
  // CHECK-LABEL: sil hidden @$s1M7AccountC7deposityySiF :
  // CHECK: ref_element_addr %1, #Account.balance
  // CHECK: begin_access [modify] [dynamic]
  func deposit(_ amount: Int = 1) { balance &+= amount }

  func applying(_ f: (Int) -> Int) -> Int { return f(balance) }

  // CHECK-LABEL: sil hidden @$s1M7AccountC7doubledSiyF :
  // CHECK-LABEL: sil private [closure] @$s1M7AccountC7doubledSiyFS2iXEfU_ :
  func doubled() -> Int { return applying { $0 &* 2 } }

  // CHECK-LABEL: sil hidden @$s1M7AccountC4makeACyFZ :
  static func make() -> Account { return Account(owner: "x") }

  // CHECK-LABEL: sil hidden @$s1M7AccountC4kindSSyFZ :
  class func kind() -> String { return "account" }
}

class Base {
  var tag = 0
  // CHECK-LABEL: sil hidden @$s1M4BaseC4bumpyyF :
  // CHECK: ref_element_addr %0, #Base.tag
  // CHECK: } // end sil function '$s1M4BaseC4bumpyyF'
  func bump() { tag &+= 1 }
}

extension Base {
  // CHECK-LABEL: sil hidden @$s1M4BaseC5twiceyyF :
  func twice() { bump(); bump() }
}

// CHECK: sil_vtable Account {
// CHECK: sil_vtable Base {
