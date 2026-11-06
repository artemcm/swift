// Phase 6.3 resolves D17: conformances compiled on demand have their witness
// tables, thunks, and conformance descriptors, so a program that uses them
// through generics and existentials links and runs. Lib.swift and Ext.swift
// are compiled on demand as one batch; main.swift, which is top-level code
// (not emitted on demand), on the legacy path in both programs. The objects
// define the same symbols as the legacy ones, and the programs print the
// same.

// REQUIRES: executable_test
// REQUIRES: concurrency
// REQUIRES: concurrency_runtime
// UNSUPPORTED: back_deployment_runtime
// RUN: %empty-directory(%t)
// RUN: split-file %s %t
// RUN: %target-swift-frontend -c -module-name M -primary-file %t/Lib.swift \
// RUN:   -primary-file %t/Ext.swift %t/main.swift -o %t/Lib.ondemand.o \
// RUN:   -o %t/Ext.ondemand.o -sil-verify-all -Xllvm -sil-on-demand-emission
// RUN: %target-swift-frontend -c -module-name M -primary-file %t/Lib.swift \
// RUN:   -primary-file %t/Ext.swift %t/main.swift -o %t/Lib.legacy.o \
// RUN:   -o %t/Ext.legacy.o
// RUN: %target-swift-frontend -c -module-name M %t/Lib.swift %t/Ext.swift \
// RUN:   -primary-file %t/main.swift -o %t/main.o
// RUN: %llvm-nm --defined-only -j %t/Lib.legacy.o | sort > %t/Lib.legacy.syms
// RUN: %llvm-nm --defined-only -j %t/Lib.ondemand.o | sort > %t/Lib.ondemand.syms
// RUN: diff %t/Lib.legacy.syms %t/Lib.ondemand.syms
// RUN: %llvm-nm --defined-only -j %t/Ext.legacy.o | sort > %t/Ext.legacy.syms
// RUN: %llvm-nm --defined-only -j %t/Ext.ondemand.o | sort > %t/Ext.ondemand.syms
// RUN: diff %t/Ext.legacy.syms %t/Ext.ondemand.syms
// RUN: %target-build-swift %t/main.o %t/Lib.ondemand.o %t/Ext.ondemand.o -o %t/ondemand.out
// RUN: %target-build-swift %t/main.o %t/Lib.legacy.o %t/Ext.legacy.o -o %t/legacy.out
// RUN: %target-codesign %t/ondemand.out
// RUN: %target-codesign %t/legacy.out
// RUN: %target-run %t/ondemand.out > %t/ondemand.txt
// RUN: %target-run %t/legacy.out > %t/legacy.txt
// RUN: diff %t/legacy.txt %t/ondemand.txt
// RUN: %FileCheck %s < %t/ondemand.txt

// CHECK: Box(3): 3
// CHECK-NEXT: [Box(1), Box(2)]
// CHECK-NEXT: wheel 4
// CHECK-NEXT: equal true, set 1
// CHECK-NEXT: {"x":1,"y":2}
// CHECK-NEXT: light dark
// CHECK-NEXT: zero one(5)
// CHECK-NEXT: counted 3
// CHECK-NEXT: default 40
// CHECK-NEXT: done

//--- Lib.swift
import Foundation

protocol Named { var name: String { get } }
protocol Measured: Named { func measure() -> Int }
extension Measured { func report() -> String { "\(name): \(measure())" } }

struct Box<T: BinaryInteger>: Measured {
  var t: T
  var name: String { "Box(\(t))" }
  func measure() -> Int { Int(t) }
}
extension Array: Named where Element: Named {
  var name: String { "[" + map(\.name).joined(separator: ", ") + "]" }
}

struct Point: Codable, Hashable { var x: Int; var y: Int }
enum Shade: String, CaseIterable { case light, dark }

protocol Make { static var zero: Self { get }; static func one(_ x: Int) -> Self }
enum Value: Make, CustomStringConvertible {
  case zero, one(Int)
  var description: String {
    switch self { case .zero: return "zero"; case .one(let x): return "one(\(x))" }
  }
}

protocol Counting { func next() async -> Int }
actor Counter: Counting { var n = 0; func next() -> Int { n += 1; return n } }

protocol Defaulted { func base() -> Int; func scaled() -> Int }
extension Defaulted { func scaled() -> Int { base() * 10 } }

func describe(_ n: some Named) -> String { n.name }
func make<T: Make>(_: T.Type) -> (T, T) { (T.zero, T.one(5)) }
func count(_ c: any Counting) async -> Int {
  var last = 0
  for _ in 0..<3 { last = await c.next() }
  return last
}

//--- Ext.swift
struct Wheel { var spokes: Int }
extension Wheel: Measured {
  var name: String { "wheel" }
  func measure() -> Int { spokes }
}
struct Four: Defaulted { func base() -> Int { 4 } }

//--- main.swift
import Foundation
print(Box(t: 3).report())
print(describe([Box(t: 1), Box(t: 2)]))
print(Wheel(spokes: 4).report().replacingOccurrences(of: ":", with: ""))
let p = Point(x: 1, y: 2)
print("equal \(p == Point(x: 1, y: 2)), set \(Set([p, p]).count)")
let encoder = JSONEncoder()
encoder.outputFormatting = .sortedKeys
print(String(data: try! encoder.encode(p), encoding: .utf8)!)
print(Shade.allCases.map(\.rawValue).joined(separator: " "))
let (z, o) = make(Value.self)
print(z, o)
print("counted \(await count(Counter()))")
print("default \(Four().scaled())")
print("done")
