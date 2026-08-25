// REQUIRES: swift_feature_LiteralExpressions

// Parenthesized generic arguments that must resolve as types, not as generic
// value expressions.
// RUN: %target-typecheck-verify-swift -disable-availability-checking -enable-experimental-feature LiteralExpressions

struct G<T> {}
struct Pair<T, U> {}
protocol P {}
protocol Q {}
protocol Container<Element> { associatedtype Element }
struct Box<E>: Container { typealias Element = E }

// =============================================================================
// Function types
//
// The parentheses open a function type, not a value expression, so the '->'
// must be consumed before the generic argument list's closing '>'.
// =============================================================================

func functionTypeInSignature(_ x: G<(Int, Int) -> Bool>) -> G<(Int) -> Void> {
  return G<(Int) -> Void>()
}

func functionTypeInExpression() {
  _ = G<(Int, Int) -> Bool>()
  _ = G<(Int, Int) -> Bool>.self
  _ = G<((Int) -> Int) -> Bool>()
  _ = G<(Int, Int) throws -> Bool>()
}

let functionTypeAlongsideValue: Pair<(Int, Int) -> Bool, (2 + 3)>? = nil
// expected-error@-1 {{cannot use value type '5' for generic argument 'U'}}

// =============================================================================
// Protocol compositions
//
// A parenthesized composition reaches the expression path as an unfolded
// SequenceExpr. The generic-argument simplifier folds it so that the
// composition is recognized as a type.
// =============================================================================

var compositionAlone: G<(P & Q)>? { nil }
var compositionInTuple: G<(Int, P & Q)>? { nil }
var existentialComposition: G<(any P & Q)>? { nil }
var existentialInTuple: G<(Int, any P)>? { nil }

// A bitwise '&' between values stays a value expression. 6 & 5 == 4.
let bitwiseAndValue: InlineArray<(6 & 5), Int> = [1, 2, 3, 4]

// =============================================================================
// Tuples and names from the enclosing protocol
//
// Resolving one of these as an expression needs unqualified value lookup, which
// in a protocol needs that protocol's requirement signature. That is what a
// structural requirement is computing, so the lookup used to report a spurious
// 'circular reference'. A name that is a type resolves as one instead.
// =============================================================================

let tupleArgument: G<(Int, String)> = G<(Int, String)>()
let parenthesizedArgument: G<(Int)> = G<Int>()
let nestedTupleArgument: G<((Int, String))> = G<(Int, String)>()

protocol SelfReferencingTuple {
  associatedtype A
  associatedtype B: Container<(A, Self)>
  associatedtype C: Container<(A)>
  associatedtype D: Container<((A, Self))>
}

struct ConformsToSelfReferencingTuple: SelfReferencingTuple {
  typealias A = Int
  typealias B = Box<(Int, ConformsToSelfReferencingTuple)>
  typealias C = Box<Int>
  typealias D = Box<(Int, ConformsToSelfReferencingTuple)>
}

// An associated type in a composition is diagnosed for what it is, rather than
// as a circular reference.
protocol AssociatedTypeInComposition {
  associatedtype A
  associatedtype B: Container<(A & Q)>
  // expected-error@-1 {{non-protocol, non-class type 'Self.A' cannot be used within a protocol-constrained type}}
}

// =============================================================================
// Value expressions still take the expression path
// =============================================================================

let sum: InlineArray<(2 + 3), Int> = [1, 2, 3, 4, 5]
let sugar: [(3 * 2) of Int] = [1, 2, 3, 4, 5, 6]
let valueAlongsideFunctionType: InlineArray<(2 + 3), (Int, Int) -> Bool>? = nil

// A tuple of values is not a generic value argument.
let tupleOfValues: InlineArray<(1, 2), Int> = [1]
// expected-error@-1 {{cannot convert value of type '(Int, Int)' to raw type 'Int'}}
// expected-error@-2 {{generic value must be an integer literal expression}}
