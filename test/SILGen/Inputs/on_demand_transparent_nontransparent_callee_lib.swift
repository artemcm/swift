// Library input for on_demand_transparent_nontransparent_callee_test.swift.
// A @_transparent function that calls a non-transparent same-module
// function. Inlining the transparent function into a cross-module
// client pulls in a reference to the non-transparent function that must
// be resolved without the MandatorySILLinker module pass.

@_transparent
public func transparentOuter(_ x: Int) -> Int {
  return nonTransparentInner(x)
}

public func nonTransparentInner(_ x: Int) -> Int {
  return x &+ 1
}
