// RUN: %empty-directory(%t)

// RUN: %target-swift-frontend -typecheck %s -diagnostic-style llvm -Wwarning PerfHintReturnTypeImplicitCopy -verify

@performanceOverride(PerfHintReturnTypeImplicitCopy, "Just Testing")
func foo() -> [Int] {
    return [1,2,3,4,5,6]
}
