// RUN: %target-typecheck-verify-swift -target %target-cpu-apple-macosx27 -target-min-inlining-version min -enable-experimental-feature LiteralExpressions

// REQUIRES: OS=macosx
// REQUIRES: swift_feature_LiteralExpressions

// A literal expression in the extended type of an extension is type-checked
// while the extended type is being resolved. Availability inferred from the
// extended type isn't known yet, so the expression is checked against the
// availability inferred from the extended nominal alone.

@available(macOS 26, *)
public struct Box<let N: Int, T> {}

@available(macOS 26.4, *)
enum Gated {
  static let count = 3
}

@available(macOS 26.4, *)
public struct Inner {}

// The extended type 'Box<3, Inner>' is as available as 'Inner', but 'Box' is
// available earlier, so 'Gated.count' is checked at the availability of 'Box'.
// expected-note@+2 {{add '@available' attribute to enclosing extension}}
// expected-error@+1 {{'Gated' is only available in macOS 26.4 or newer}}
extension Box<(Gated.count), Inner> {
  public func onGatedArgument() {}
}

// Explicit platform availability on the extension avoids the inference.
@available(macOS 26.4, *)
extension Box<(Gated.count), Gated> {
  public func onExplicitlyAvailable() {}
}

// An internal extension is checked at the deployment target.
extension Box<(Gated.count), Int> {
  func onInternal() {}
}
