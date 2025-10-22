// REQUIRES: swift_in_compiler
// REQUIRES: swift_feature_SourceWarningControl
// REQUIRES: rdar132141321

// RUN: %target-typecheck-verify-swift -enable-experimental-feature SourceWarningControl -suppress-warnings

@available(*, deprecated)
func dep() {}

func foo() {
    dep() // expected-silence
    @warn(DeprecatedDeclaration, as: warning)
    func bar() {
        dep() // expected-warning {{'dep()' is deprecated}}
        @warn(DeprecatedDeclaration, as: error)
        func baz() {
            dep() // expected-error {{'dep()' is deprecated}}
            @warn(DeprecatedDeclaration, as: ignored)
            func qux() {
                dep() // expected-silence
            }
        }
    }
}

