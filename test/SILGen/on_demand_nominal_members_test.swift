// Phase 6.1: on demand, the coordinator emits the members of structs and enums
// and their extensions in legacy order, routing each member's auxiliaries
// through AuxiliaryDeclEmissionRequest. The output equals legacy's, whole
// module, single primary, and batch. The inputs cover the struct and enum
// cases of the test list in LazyCompiler/Plans/Phase6-Plan.md.
//
// Uses.swift's outputs are compared after sil_sort_external_entities.py: they
// differ only in the order in which the linker deserialized other modules'
// functions. Legacy links the whole module after inlining all of it; on
// demand, OnDemandSILLinker links each function as it is canonicalized.

// RUN: %empty-directory(%t)
// RUN: split-file %s %t

// Whole module.
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   %t/Types.swift %t/Enums.swift %t/Uses.swift -o %t/wmo.legacy.sil
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   %t/Types.swift %t/Enums.swift %t/Uses.swift -o %t/wmo.ondemand.sil \
// RUN:   -sil-verify-all -Xllvm -sil-on-demand-emission
// RUN: diff %t/wmo.legacy.sil %t/wmo.ondemand.sil
// RUN: %FileCheck %s < %t/wmo.ondemand.sil

// Each file as the single primary.
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   -primary-file %t/Types.swift %t/Enums.swift %t/Uses.swift \
// RUN:   -o %t/Types.legacy.sil
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   -primary-file %t/Types.swift %t/Enums.swift %t/Uses.swift \
// RUN:   -o %t/Types.ondemand.sil -Xllvm -sil-on-demand-emission
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   %t/Types.swift -primary-file %t/Enums.swift %t/Uses.swift \
// RUN:   -o %t/Enums.legacy.sil
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   %t/Types.swift -primary-file %t/Enums.swift %t/Uses.swift \
// RUN:   -o %t/Enums.ondemand.sil -Xllvm -sil-on-demand-emission
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   %t/Types.swift %t/Enums.swift -primary-file %t/Uses.swift \
// RUN:   -o %t/Uses.legacy.sil
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   %t/Types.swift %t/Enums.swift -primary-file %t/Uses.swift \
// RUN:   -o %t/Uses.ondemand.sil -Xllvm -sil-on-demand-emission
// RUN: diff %t/Types.legacy.sil %t/Types.ondemand.sil
// RUN: diff %t/Enums.legacy.sil %t/Enums.ondemand.sil
// RUN: %{python} %S/Inputs/sil_sort_external_entities.py M \
// RUN:   < %t/Uses.legacy.sil > %t/Uses.legacy.sorted.sil
// RUN: %{python} %S/Inputs/sil_sort_external_entities.py M \
// RUN:   < %t/Uses.ondemand.sil > %t/Uses.ondemand.sorted.sil
// RUN: diff %t/Uses.legacy.sorted.sil %t/Uses.ondemand.sorted.sil

// Batch: every file a primary, in one frontend invocation.
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   -primary-file %t/Types.swift -primary-file %t/Enums.swift \
// RUN:   -primary-file %t/Uses.swift -o %t/Types.batch.legacy.sil \
// RUN:   -o %t/Enums.batch.legacy.sil -o %t/Uses.batch.legacy.sil
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   -primary-file %t/Types.swift -primary-file %t/Enums.swift \
// RUN:   -primary-file %t/Uses.swift -o %t/Types.batch.ondemand.sil \
// RUN:   -o %t/Enums.batch.ondemand.sil -o %t/Uses.batch.ondemand.sil \
// RUN:   -Xllvm -sil-on-demand-emission
// RUN: diff %t/Types.batch.legacy.sil %t/Types.batch.ondemand.sil
// RUN: diff %t/Enums.batch.legacy.sil %t/Enums.batch.ondemand.sil
// RUN: %{python} %S/Inputs/sil_sort_external_entities.py M \
// RUN:   < %t/Uses.batch.legacy.sil > %t/Uses.batch.legacy.sorted.sil
// RUN: %{python} %S/Inputs/sil_sort_external_entities.py M \
// RUN:   < %t/Uses.batch.ondemand.sil > %t/Uses.batch.ondemand.sorted.sil
// RUN: diff %t/Uses.batch.legacy.sorted.sil %t/Uses.batch.ondemand.sorted.sil
// On demand, batch output equals single-primary output (F1).
// RUN: diff %t/Types.batch.ondemand.sil %t/Types.ondemand.sil
// RUN: diff %t/Enums.batch.ondemand.sil %t/Enums.ondemand.sil
// RUN: diff %t/Uses.batch.ondemand.sil %t/Uses.ondemand.sil

// The diffs above aren't vacuous: one function per construct.
// CHECK-LABEL: sil hidden @$s1M5PointV3sumSiyF :
// CHECK-LABEL: sil hidden @$s1M5PointV6originACyFZ :
// CHECK-LABEL: sil hidden @$s1M5PointV1x1yACSi_SitcfC :
// CHECK-LABEL: sil private [closure] @$s1M5PointV7doubledACyFS2iXEfU_ :
// CHECK-LABEL: sil hidden [transparent] @$s1M7CounterV5countSivpfi :
// CHECK-LABEL: sil hidden @$s1M7CounterV9increment2byySi_tFfA_ :
// CHECK-LABEL: sil hidden @$s1M3BoxV3mapyACyqd__Gqd__xXElF :
// CHECK-LABEL: sil hidden @$s1M6HandleVfD :
// CHECK-LABEL: sil hidden @$s1M11TemperatureV10fahrenheitSdvs :
// CHECK-LABEL: sil hidden @$s1M7StorageV5itemsSaySiGvr :
// CHECK-LABEL: sil hidden @$s1M7StorageV5itemsSaySiGvM :
// CHECK-LABEL: sil hidden @$s1M4GridVyS2i_SitcipfA0_ :
// CHECK-LABEL: sil hidden @$s1M6SummerV5totalySixSlRzSi7ElementRtzlF :
// CHECK-LABEL: sil hidden @$s1M6VolumeV5levelSivpfP :
// CHECK-LABEL: sil @$s1M3VecV6scaledyACSiF :
// CHECK-LABEL: sil private [closure] @$s1M7GreeterV8greetingSSycyFSSycfU_ :
// CHECK-LABEL: sil private [closure] @$s1M6ConfigV6valuesSaySiGvpfiAEyXEfU_ :
// CHECK-LABEL: sil hidden @$s1M5ShapeO4rectyACSd_SdtcACmFfA0_ :
// CHECK-LABEL: sil hidden @$s1M4ExprO4evalSiyF :

//--- Types.swift
// 1. Struct method (no closures); a static method; the implicit memberwise init.
struct Point {
  var x: Int
  var y: Int
  func sum() -> Int { return x &+ y }
  mutating func shift(by d: Int) { x &+= d; y &+= d }
  static func origin() -> Point { return Point(x: 0, y: 0) }
}

// 2. Struct method with a closure literal, in an extension.
extension Point {
  func mapped(_ f: (Int) -> Int) -> Point { return Point(x: f(x), y: f(y)) }
  func doubled() -> Point { return mapped { $0 &* 2 } }
}

// 3. Struct method with a default argument; a stored property initializer.
struct Counter {
  var count = 0
  mutating func increment(by step: Int = 1) { count &+= step }
}

// 4. Generic struct method.
struct Box<T> {
  var value: T
  func get() -> T { return value }
  func map<U>(_ f: (T) -> U) -> Box<U> { return Box<U>(value: f(value)) }
}

// 5. Move-only struct destructor.
func closeHandle(_ fd: Int) {}
struct Handle: ~Copyable {
  var fd: Int
  init(fd: Int) { self.fd = fd }
  deinit { closeHandle(fd) }
  consuming func release() -> Int { let x = fd; discard self; return x }
}

// 6. Computed property (get and set).
struct Temperature {
  var celsius: Double
  var fahrenheit: Double {
    get { return celsius * 9 / 5 + 32 }
    set { celsius = (newValue - 32) * 5 / 9 }
  }
}

// 7. Read and modify coroutine accessors.
struct Storage {
  var _items: [Int] = []
  var items: [Int] {
    _read { yield _items }
    _modify { yield &_items }
  }
}

// 8. Subscript with a default argument.
struct Grid {
  var cols: Int
  var cells: [Int]
  subscript(row: Int, column: Int = 0) -> Int {
    get { return cells[row &* cols &+ column] }
    set { cells[row &* cols &+ column] = newValue }
  }
}

// 9. Generic method with associated-type constraints.
struct Summer {
  func total<C: Collection>(_ c: C) -> Int where C.Element == Int {
    var t = 0
    for e in c { t &+= e }
    return t
  }
}

// 10. Property wrapper applied to a stored property.
@propertyWrapper
struct Clamped {
  var value: Int
  let limit: Int
  init(wrappedValue: Int, limit: Int) {
    self.limit = limit
    self.value = wrappedValue < limit ? wrappedValue : limit
  }
  var wrappedValue: Int {
    get { return value }
    set { value = newValue < limit ? newValue : limit }
  }
}
struct Volume {
  @Clamped(limit: 10) var level: Int = 5
}

// 13. @inlinable method of a public struct.
public struct Vec {
  public var x: Int
  public init(x: Int) { self.x = x }
  @inlinable public func scaled(_ k: Int) -> Vec { return Vec(x: x &* k) }
}

// 14. Closure capturing self.
struct Greeter {
  var name: String
  func greeting() -> () -> String { return { "Hello, " + self.name } }
}

// 15. Stored property initializer with a closure, shared by two initializers.
struct Config {
  var values: [Int] = { [1, 2, 3].map { $0 &* 2 } }()
  var flag: Bool
  init() { flag = false }
  init(flag: Bool) { self.flag = flag }
}

//--- Enums.swift
// 11. Enum with associated values, a payload default argument, and members.
enum Shape {
  case circle(radius: Double)
  case rect(width: Double, height: Double = 1)
  case empty

  var area: Double {
    switch self {
    case .circle(let r): return 3 * r * r
    case .rect(let w, let h): return w * h
    case .empty: return 0
    }
  }
  func scaled(by k: Double) -> Shape {
    switch self {
    case .circle(let r): return .circle(radius: r * k)
    case .rect(let w, let h): return .rect(width: w * k, height: h * k)
    case .empty: return .empty
    }
  }
  static func unit() -> Shape { return .rect(width: 1) }
  init(side: Double) { self = .rect(width: side, height: side) }
}

// 12. Indirect enum case.
indirect enum Expr {
  case num(Int)
  case add(Expr, Expr)
  func eval() -> Int {
    switch self {
    case .num(let n): return n
    case .add(let a, let b): return a.eval() &+ b.eval()
    }
  }
}

extension Expr {
  static func sum(_ xs: [Int]) -> Expr {
    var e = Expr.num(0)
    for x in xs { e = .add(e, .num(x)) }
    return e
  }
}

// An enum case constructor used as a function value.
func makeCircles(_ rs: [Double]) -> [Shape] { return rs.map(Shape.circle) }

//--- Uses.swift
func usePoint() -> Int {
  var p = Point.origin()
  p.shift(by: 2)
  return p.doubled().sum()
}
func useCounter() -> Int { var c = Counter(); c.increment(); c.increment(by: 3); return c.count }
func useBox() -> String { return Box(value: 3).map { "\($0)" }.get() }
func useHandle() -> Int { let h = Handle(fd: 3); return h.release() }
func useTemperature() -> Double { var t = Temperature(celsius: 20); t.fahrenheit = 50; return t.celsius }
func useStorage() -> Int { var s = Storage(); s.items.append(1); return s.items.count }
func useGrid() -> Int { var g = Grid(cols: 2, cells: [1, 2, 3, 4]); g[1] = 7; return g[1, 1] }
func useSummer() -> Int { return Summer().total([1, 2, 3]) }
func useVolume() -> Int { var v = Volume(); v.level = 20; return v.level }
func useVec() -> Int { return Vec(x: 2).scaled(3).x }
func useGreeter() -> String { return Greeter(name: "x").greeting()() }
func useConfig() -> Int { return Config().values.count &+ Config(flag: true).values.count }
func useShapes() -> Double {
  let shapes = makeCircles([1, 2]) + [Shape.unit(), Shape(side: 2), .empty]
  return shapes.map { $0.scaled(by: 2).area }.reduce(0, +)
}
func useExpr() -> Int { return Expr.sum([1, 2, 3]).eval() }
func useCaseConstructor() -> [Expr] { return [1, 2].map(Expr.num) }
