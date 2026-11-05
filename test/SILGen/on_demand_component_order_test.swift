// On demand, DiagnosedSILFunctionRequest runs the function-only pipeline over
// a closure component in one scoped run. Legacy's pass manager runs each span
// of function passes over callees before callers, and FlowIsolation depends
// on that: it analyzes the defer body that an initializer calls, and needs
// NoReturnFolding to have run on it, so that the path ending in fatalError
// doesn't carry nonisolation out. The scoped run now orders each span
// bottom-up too, and this initializer gets no diagnostic on either path.

// RUN: %target-swift-frontend -strict-concurrency=complete -swift-version 5 \
// RUN:   -parse-as-library -emit-sil -verify %s -o /dev/null
// RUN: %target-swift-frontend -strict-concurrency=complete -swift-version 5 \
// RUN:   -parse-as-library -emit-sil -verify %s -o /dev/null \
// RUN:   -Xllvm -sil-on-demand-emission

func randomBool() -> Bool { return false }

actor Bob {
  var x: Int
  nonisolated func speak() {}

  init(spice doesNotFlow: Int) {
    if true {
      defer {
        if randomBool() {
          speak()
          fatalError("oops")
        }
      }
      self.x = 0
    }
    self.x = 20
  }
}
