// Phase 6.2 doesn't emit Objective-C entry points on demand: the @objc
// thunks, and the destructors of a class that uses the Objective-C
// allocator, wait for Phase 6.5. Instead of emitting an incomplete class,
// the coordinator rejects them. Legacy compiles this file.

// REQUIRES: objc_interop
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M %s \
// RUN:   -o /dev/null
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M %s \
// RUN:   -o /dev/null -verify -Xllvm -sil-on-demand-emission

import Foundation

// expected-error@+1 {{feature not implemented: on-demand SIL emission of Objective-C entry points}}
class Obj: NSObject {
  func f() {}
}

class Native {
  // expected-error@+1 {{feature not implemented: on-demand SIL emission of Objective-C entry points}}
  @objc func g() {}
  func h() {}
}

extension Native {
  // expected-error@+1 {{feature not implemented: on-demand SIL emission of Objective-C entry points}}
  @objc var k: Int { return 1 }
}
