// -Xllvm options are process-wide, so a module that a compile builds from its
// interface sees -sil-on-demand-emission too. Such a lowering stays on the
// legacy path: the on-demand coordinator doesn't emit all of a module, and
// the module cache keeps the module for later compiles. Before, building a
// module from an interface on demand aborted on the first initializer
// without a body.

// RUN: %empty-directory(%t)
// RUN: split-file %s %t
// RUN: %target-swift-frontend -emit-module -module-name Lib %t/Lib.swift \
// RUN:   -swift-version 5 -enable-library-evolution \
// RUN:   -emit-module-interface-path %t/Interfaces/Lib.swiftinterface \
// RUN:   -o %t/Lib.unused.swiftmodule

// An explicit build: the on-demand flag changes nothing.
// RUN: %target-swift-frontend -compile-module-from-interface -module-name Lib \
// RUN:   %t/Interfaces/Lib.swiftinterface -o %t/Lib.legacy.swiftmodule
// RUN: %target-swift-frontend -compile-module-from-interface -module-name Lib \
// RUN:   %t/Interfaces/Lib.swiftinterface -o %t/Lib.ondemand.swiftmodule \
// RUN:   -Xllvm -sil-on-demand-emission
// RUN: cmp %t/Lib.legacy.swiftmodule %t/Lib.ondemand.swiftmodule

// An implicit build, from a client compiled on demand.
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name Client \
// RUN:   %t/Client.swift -I %t/Interfaces -module-cache-path %t/ModuleCache \
// RUN:   -o %t/Client.sil -Xllvm -sil-on-demand-emission
// RUN: %FileCheck %s < %t/Client.sil
// CHECK-LABEL: sil @$s6Client3useSiyF : $@convention(thin) () -> Int {

//--- Lib.swift
open class Base {
  public var tag: Int
  public init(tag: Int) { self.tag = tag }
  public convenience init() { self.init(tag: 0) }
  deinit {}
  open func f() -> Int { return tag }
}

public struct P {
  public var x: Int
  public init(x: Int) { self.x = x }
}

@inlinable public func make() -> Base { return Base(tag: 1) }
@inlinable public func makeP() -> P { return P(x: 1) }

//--- Client.swift
import Lib

public func use() -> Int { return make().f() &+ makeP().x }
