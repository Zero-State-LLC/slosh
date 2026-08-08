import Foundation

/// A minimal check harness. XCTest only ships with Xcode, and this suite needs
/// to run anywhere the Swift toolchain does — including CI images and a Mac
/// with only the command line tools installed.
enum Check {
    nonisolated(unsafe) static var failures: [String] = []
    nonisolated(unsafe) static var checksRun = 0
    nonisolated(unsafe) private static var currentSuite = ""
    nonisolated(unsafe) private static var currentTest = ""
    nonisolated(unsafe) private static var failuresBeforeTest = 0

    static func suite(_ name: String, _ body: () -> Void) {
        currentSuite = name
        print("\n\(name)")
        body()
    }

    static func test(_ name: String, _ body: () -> Void) {
        currentTest = name
        failuresBeforeTest = failures.count
        body()
        let passed = failures.count == failuresBeforeTest
        print("  \(passed ? "✓" : "✗") \(name)")
    }

    private static func fail(_ message: String) {
        failures.append("\(currentSuite) › \(currentTest): \(message)")
    }

    static func expect(_ condition: Bool, _ message: @autoclosure () -> String) {
        checksRun += 1
        if !condition { fail(message()) }
    }

    static func equal(
        _ actual: Double,
        _ expected: Double,
        accuracy: Double = 1e-9,
        _ message: @autoclosure () -> String = ""
    ) {
        checksRun += 1
        guard actual.isFinite, expected.isFinite, abs(actual - expected) <= accuracy else {
            fail("expected \(expected) ± \(accuracy), got \(actual). \(message())")
            return
        }
    }

    static func equal<T: Equatable>(
        _ actual: T,
        _ expected: T,
        _ message: @autoclosure () -> String = ""
    ) {
        checksRun += 1
        if actual != expected {
            fail("expected \(expected), got \(actual). \(message())")
        }
    }

    static func lessThan(
        _ lhs: Double, _ rhs: Double, _ message: @autoclosure () -> String = ""
    ) {
        checksRun += 1
        if !(lhs < rhs) { fail("expected \(lhs) < \(rhs). \(message())") }
    }

    static func greaterThan(
        _ lhs: Double, _ rhs: Double, _ message: @autoclosure () -> String = ""
    ) {
        checksRun += 1
        if !(lhs > rhs) { fail("expected \(lhs) > \(rhs). \(message())") }
    }

    static func report() -> Int32 {
        print("\n" + String(repeating: "─", count: 52))
        if failures.isEmpty {
            print("All \(checksRun) checks passed.")
            return 0
        }
        print("\(failures.count) failure(s) out of \(checksRun) checks:\n")
        for failure in failures { print("  • \(failure)") }
        return 1
    }
}

/// Reproducible pseudo-randomness, so a failing run can be re-run identically.
struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64 = 0x5EED_1234_ABCD_0001) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
