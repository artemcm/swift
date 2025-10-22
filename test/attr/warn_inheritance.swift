// REQUIRES: swift_in_compiler
// REQUIRES: swift_feature_SourceWarningControl

// RUN: %target-typecheck-verify-swift -enable-experimental-feature SourceWarningControl -Wwarning PerformanceHints

@warn(ReturnTypeImplicitCopy, as: error)
func foo() -> [Int] { // expected-error {{Performance: 'foo()' returns an array, leading to implicit copies. Consider using an 'inout' parameter instead}}
    @warn(PerformanceHints, as: ignored)
    func qux() -> [Int] { // expected-silence
        @warn(ReturnTypeImplicitCopy, as: error)
        func quux() -> [Int] { // expected-error {{Performance: 'quux()' returns an array, leading to implicit copies. Consider using an 'inout' parameter instead}}
            return []
        }
        return []
    }
    return []
}
