// RUN: %target-typecheck-verify-swift

// To find out whether a pattern such as 'A.b' names an enum case, pattern
// resolution first resolves 'A' as a type with diagnostics silenced. If that
// fails, the pattern is type-checked as an expression instead. The silenced
// type resolution must not diagnose anything, so that each problem below is
// reported once, by the expression.

protocol PA {
  associatedtype Assoc
}

// A dependent member type that does not exist.
func dependentMember<T: PA>(_ x: Any, _: T) {
  switch x {
  case T.Missing.a: // expected-error {{type 'T' has no member 'Missing'}}
    break
  default:
    break
  }
}

// A nested type whose contextual requirements are not satisfied.
struct Outer<T> {}

extension Outer where T == Int { // expected-note {{requirement specified as 'T' == 'Int' [with T = T]}}
  enum Nested {
    case a
  }
}

extension Outer {
  func contextualRequirements(_ x: Any) {
    switch x {
    case Nested.a: // expected-error {{'Outer<T>.Nested' requires the types 'T' and 'Int' be equivalent}}
      break
    default:
      break
    }
  }
}

// A type pack referenced without 'each'.
func packReference<each T>(_ x: Any, _: repeat each T) {
  switch x {
  case T.a: // expected-error {{type pack 'T' must be referenced with 'each'}}
    break
  default:
    break
  }
}
