// REQUIRES: swift_in_compiler
// REQUIRES: swift_feature_SourceWarningControl

// RUN: %target-typecheck-verify-swift -enable-experimental-feature SourceWarningControl -Werror DeprecatedDeclaration
// RUN: %target-typecheck-verify-swift -enable-experimental-feature SourceWarningControl -warnings-as-errors

@available(*, deprecated)
func dep() {}

func foo() {
    dep() // expected-error {{'dep()' is deprecated}}
    @warn(DeprecatedDeclaration, as: warning)
    func bar() {
        dep() // expected-warning {{'dep()' is deprecated}}
        @warn(DeprecatedDeclaration, as: ignored)
        func baz() {
            dep() // expected-silence
        }        
    }
}

