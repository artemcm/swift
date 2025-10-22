// REQUIRES: swift_in_compiler
// REQUIRES: swift_feature_SourceWarningControl

// RUN: %target-typecheck-verify-swift -enable-experimental-feature SourceWarningControl

@available(*, deprecated)
func dep() {}

func foo() {
    dep() // expected-warning {{'dep()' is deprecated}}
    @warn(DeprecatedDeclaration, as: error)
    func bar() {
        dep() // expected-error {{'dep()' is deprecated}}
        @warn(DeprecatedDeclaration, as: warning)
        func baz() {
            dep() // expected-warning {{'dep()' is deprecated}}
            @warn(DeprecatedDeclaration, as: ignored)
            func qux() {
                dep() // expected-silence
                @warn(DeprecatedDeclaration, as: error)
                func quux() {
                    dep() // expected-error {{'dep()' is deprecated}}
                }
            }
        }        
    }
}

