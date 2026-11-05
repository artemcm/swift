// Phase 6.2 resolves D7: a class compiled on demand has its vtable, its
// initializers and destructors, and its accessors, so IRGen emits its
// metadata. The on-demand object defines the same symbols as the legacy
// one, and a program linked from it behaves the same.

// REQUIRES: executable_test
// RUN: %empty-directory(%t)
// RUN: split-file %s %t
// RUN: %target-swift-frontend -c -module-name M -primary-file %t/Lib.swift \
// RUN:   %t/main.swift -o %t/Lib.ondemand.o -Xllvm -sil-on-demand-emission
// RUN: %target-swift-frontend -c -module-name M -primary-file %t/Lib.swift \
// RUN:   %t/main.swift -o %t/Lib.legacy.o
// RUN: %target-swift-frontend -c -module-name M %t/Lib.swift \
// RUN:   -primary-file %t/main.swift -o %t/main.o
// RUN: %llvm-nm --defined-only -j %t/Lib.legacy.o | sort > %t/legacy.syms
// RUN: %llvm-nm --defined-only -j %t/Lib.ondemand.o | sort > %t/ondemand.syms
// RUN: diff %t/legacy.syms %t/ondemand.syms
// RUN: %target-build-swift %t/main.o %t/Lib.ondemand.o -o %t/ondemand.out
// RUN: %target-build-swift %t/main.o %t/Lib.legacy.o -o %t/legacy.out
// RUN: %target-codesign %t/ondemand.out
// RUN: %target-codesign %t/legacy.out
// RUN: %target-run %t/ondemand.out > %t/ondemand.txt
// RUN: %target-run %t/legacy.out > %t/legacy.txt
// RUN: diff %t/legacy.txt %t/ondemand.txt
// RUN: %FileCheck %s < %t/ondemand.txt

// CHECK: square: 9
// CHECK-NEXT: square of 3
// CHECK-NEXT: sides 0 -> 4
// CHECK-NEXT: 8
// CHECK-NEXT: square
// CHECK-NEXT: square' 1
// CHECK-NEXT: 42
// CHECK-NEXT: shape anon
// CHECK-DAG: deinit Square
// CHECK-DAG: deinit Shape square'
// CHECK-DAG: deinit Shape anon
// CHECK: done

//--- Lib.swift
public class Shape {
  public let name: String
  public var sides: Int = 0 { didSet { print("sides", oldValue, "->", sides) } }
  public lazy var label: String = "shape " + name
  public weak var peer: Shape?
  public init(name: String) { self.name = name }
  public convenience init() { self.init(name: "anon") }
  public required init(copy other: Shape) { self.name = other.name + "'" }
  public func area() -> Int { return 0 }
  public func describe() -> String? { return nil }
  public subscript(i: Int) -> Int { return sides &* i }
  public class func kind() -> String { return "shape" }
  deinit { print("deinit Shape", name) }
}

public final class Square: Shape {
  var edge: [Int]
  public init(edge: Int) {
    self.edge = [edge]
    super.init(name: "square")
  }
  public required init(copy other: Shape) {
    edge = [1]
    super.init(copy: other)
  }
  public override func area() -> Int { return edge[0] &* edge[0] }
  // String? to String: dispatched through a vtable thunk.
  public override func describe() -> String { return "square of \(edge[0])" }
  public override class func kind() -> String { return "square" }
  deinit { print("deinit Square") }
}

open class Box<T> {
  open var value: T
  public init(_ v: T) { value = v }
  open func get() -> T { return value }
}

public final class IntBox: Box<Int> {
  public override func get() -> Int { return value &+ 1 }
}

extension Shape {
  public func summary() -> String { return "\(name): \(area())" }
}

//--- main.swift
func run() {
  let s: Shape = Square(edge: 3)
  print(s.summary())
  print(s.describe() ?? "nil")
  s.sides = 4
  print(s[2])
  print(type(of: s).kind())
  let c = type(of: s).init(copy: s)
  print(c.name, c.area())
  let b: Box<Int> = IntBox(41)
  print(b.get())
  let p = Shape()
  p.peer = c
  print(p.label)
}
run()
print("done")
