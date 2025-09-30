// RUN: %empty-directory(%t)

// Ensure diagnosed as error by-default
// RUN: not %target-swift-frontend -typecheck %s -diagnostic-style llvm &> %t/output_err.txt
// RUN: cat %t/output_err.txt | %FileCheck %s

// Ensure ignored by-default
// RUN: %target-swift-frontend -typecheck %s -diagnostic-style llvm -verify

// Ensure enabled with '-Wwarning'
// RUN: %target-swift-frontend -typecheck %s -diagnostic-style llvm -Wwarning PerfHintReturnTypeImplicitCopy &> %t/output_warn.txt
// RUN: cat %t/output_warn.txt | %FileCheck %s -check-prefix CHECK-WARN

// Ensure escalated with '-Werror'
// RUN: %target-swift-frontend -typecheck %s -diagnostic-style llvm -Werror PerfHintReturnTypeImplicitCopy &> %t/output_err.txt
// RUN: cat %t/output_err.txt | %FileCheck %s -check-prefix CHECK-ERR

// CHECK-ERR: error: Performance: 'foo()' returns an array, leading to implicit copies. Consider using an 'inout' parameter instead. [#PerfHintReturnTypeImplicitCopy]
// CHECK-ERR: error: Performance: closure returns an array, leading to implicit copies. Consider using an 'inout' parameter instead. [#PerfHintReturnTypeImplicitCopy]

// CHECK-WARN: warning: Performance: 'foo()' returns an array, leading to implicit copies. Consider using an 'inout' parameter instead. [#PerfHintReturnTypeImplicitCopy]
// CHECK-WARN: warning: Performance: closure returns an array, leading to implicit copies. Consider using an 'inout' parameter instead. [#PerfHintReturnTypeImplicitCopy]

func foo() -> [Int] {
    return [1,2,3,4,5,6]
}

func bar() -> Int {
    let myCoolArray = { () -> [Int] in
        return [1, 2]
    }
    return myCoolArray().count
}
