// Phase 6.6 resolves D23: on demand, the entry points are emitted, as on the
// legacy path: a script-mode file's main, before the file's declarations,
// with its top-level code and globals; an async script's async_Main; and an
// @main type's main (and async_Main if its main is async), after the file's
// declarations. So a program links from objects lowered on demand only.

// REQUIRES: executable_test
// REQUIRES: concurrency
// REQUIRES: concurrency_runtime
// UNSUPPORTED: back_deployment_runtime

// RUN: %empty-directory(%t)
// RUN: split-file %s %t

// A script and a library file.
// RUN: %target-swift-frontend -emit-sil -module-name M %t/Script/main.swift \
// RUN:   %t/Script/Lib.swift -o %t/script.legacy.sil
// RUN: %target-swift-frontend -emit-sil -module-name M %t/Script/main.swift \
// RUN:   %t/Script/Lib.swift -o %t/script.ondemand.sil -sil-verify-all \
// RUN:   -Xllvm -sil-on-demand-emission
// RUN: %{python} %S/Inputs/sil_sort_external_entities.py M \
// RUN:   < %t/script.legacy.sil > %t/script.legacy.sorted.sil
// RUN: %{python} %S/Inputs/sil_sort_external_entities.py M \
// RUN:   < %t/script.ondemand.sil > %t/script.ondemand.sorted.sil
// RUN: diff %t/script.legacy.sorted.sil %t/script.ondemand.sorted.sil
// RUN: %FileCheck --check-prefix=SCRIPT %s < %t/script.ondemand.sil
// RUN: %target-swift-frontend -c -module-name M \
// RUN:   -primary-file %t/Script/main.swift -primary-file %t/Script/Lib.swift \
// RUN:   -o %t/script.main.o -o %t/script.lib.o -sil-verify-all \
// RUN:   -Xllvm -sil-on-demand-emission
// RUN: %target-build-swift %t/script.main.o %t/script.lib.o -o %t/script.out
// RUN: %target-codesign %t/script.out
// RUN: %target-run %t/script.out > %t/script.txt
// RUN: %FileCheck --check-prefix=SCRIPTOUT %s < %t/script.txt

// An async script. Opened-archetype IDs come from a counter of the whole
// compilation, so they depend on the order of emission: normalized.
// RUN: %target-swift-frontend -emit-sil -module-name M %t/Async/main.swift \
// RUN:   -o %t/async.legacy.sil
// RUN: %target-swift-frontend -emit-sil -module-name M %t/Async/main.swift \
// RUN:   -o %t/async.ondemand.sil -sil-verify-all -Xllvm -sil-on-demand-emission
// RUN: %{python} %S/Inputs/sil_sort_external_entities.py M \
// RUN:   < %t/async.legacy.sil | sed -E 's/@opened\([0-9]+,/@opened(N,/g' > %t/async.legacy.sorted.sil
// RUN: %{python} %S/Inputs/sil_sort_external_entities.py M \
// RUN:   < %t/async.ondemand.sil | sed -E 's/@opened\([0-9]+,/@opened(N,/g' > %t/async.ondemand.sorted.sil
// RUN: diff %t/async.legacy.sorted.sil %t/async.ondemand.sorted.sil
// RUN: %FileCheck --check-prefix=ASYNC %s < %t/async.ondemand.sil
// RUN: %target-swift-frontend -c -module-name M %t/Async/main.swift \
// RUN:   -o %t/async.o -Xllvm -sil-on-demand-emission
// RUN: %target-build-swift %t/async.o -o %t/async.out
// RUN: %target-codesign %t/async.out
// RUN: %target-run %t/async.out > %t/async.txt
// RUN: %FileCheck --check-prefix=ASYNCOUT %s < %t/async.txt

// @main on a struct, an enum, and a class whose main is async and throws.
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   %t/MainStruct.swift -o %t/struct.legacy.sil
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   %t/MainStruct.swift -o %t/struct.ondemand.sil -sil-verify-all \
// RUN:   -Xllvm -sil-on-demand-emission
// RUN: diff %t/struct.legacy.sil %t/struct.ondemand.sil
// RUN: %FileCheck --check-prefix=STRUCT %s < %t/struct.ondemand.sil
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   %t/MainEnum.swift -o %t/enum.legacy.sil
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   %t/MainEnum.swift -o %t/enum.ondemand.sil -sil-verify-all \
// RUN:   -Xllvm -sil-on-demand-emission
// RUN: diff %t/enum.legacy.sil %t/enum.ondemand.sil
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   %t/MainClass.swift -o %t/class.legacy.sil
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   %t/MainClass.swift -o %t/class.ondemand.sil -sil-verify-all \
// RUN:   -Xllvm -sil-on-demand-emission
// RUN: diff %t/class.legacy.sil %t/class.ondemand.sil
// RUN: %FileCheck --check-prefix=CLASS %s < %t/class.ondemand.sil
// RUN: %target-swift-frontend -c -parse-as-library -module-name M \
// RUN:   %t/MainClass.swift -o %t/class.o -Xllvm -sil-on-demand-emission
// RUN: %target-build-swift %t/class.o -o %t/class.out
// RUN: %target-codesign %t/class.out
// RUN: %target-run %t/class.out > %t/class.txt
// RUN: %FileCheck --check-prefix=CLASSOUT %s < %t/class.txt

// SCRIPT: sil_global hidden @$s1M5totalSivp : $Int
// SCRIPT: sil @main : $@convention(c) (Int32, UnsafeMutablePointer<Optional<UnsafeMutablePointer<Int8>>>) -> Int32 {
// SCRIPTOUT: 1
// SCRIPTOUT-NEXT: deferred
// SCRIPTOUT-NEXT: caught Failure()
// SCRIPTOUT-NEXT: 10 [12, 14, 16, 18] lib
// ASYNC: sil private @async_Main : $@convention(thin) @async () -> () {
// ASYNCOUT: 18 54
// STRUCT: sil @main : $@convention(c) (Int32, UnsafeMutablePointer<Optional<UnsafeMutablePointer<Int8>>>) -> Int32 {
// CLASS-DAG: sil @main : $@convention(c) (Int32, UnsafeMutablePointer<Optional<UnsafeMutablePointer<Int8>>>) -> Int32 {
// CLASS-DAG: sil private @async_Main : $@convention(thin) @async () -> () {
// CLASSOUT: class main 2

//--- Script/main.swift
var total = 0
let items = [1, 2, 3, 4]
func add(_ x: Int) { total += x }
for i in items { add(i) }
let doubled = items.map { $0 * 2 + total }
struct Failure: Error {}
func risky(_ x: Int) throws -> Int { if x > 2 { throw Failure() }; return x }
do {
  defer { print("deferred") }
  print(try risky(1))
  print(try risky(5))
} catch {
  print("caught", error)
}
guard total == 10 else { fatalError("total") }
print(total, doubled, libName())

//--- Script/Lib.swift
func libName() -> String { "lib" }

//--- Async/main.swift
func work(_ x: Int) async -> Int { x * 3 }
var acc = 0
for i in 1...3 { acc += await work(i) }
let t = Task { await work(acc) }
print(acc, await t.value)

//--- MainStruct.swift
@main struct App {
  static var runs = 0
  static func main() { runs += 1; print("struct main", runs) }
}

//--- MainEnum.swift
let greeting = "enum main"
@main enum App {
  static func main() throws { print(greeting) }
}

//--- MainClass.swift
struct Oops: Error {}
func step(_ x: Int) async throws -> Int { if x < 0 { throw Oops() }; return x + 1 }
@main final class App {
  static func main() async throws { print("class main", try await step(1)) }
}
