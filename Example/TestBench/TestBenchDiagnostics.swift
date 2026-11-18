import DebugDrawerAnalyticsPlugin
import DebugDrawerLeakDetectorPlugin
import Foundation

/// Problems on demand for the plugins that catch them: an analytics event, leaked objects, a hang
/// and a crash.
@MainActor
enum TestBenchDiagnostics {
    /// Records an event with properties of a few kinds, as the app would beside its SDK's call.
    static func trackEvent() async -> String {
        AnalyticsEvents.record("test_bench_action", properties: ["screen": "Test Bench", "count": 1, "debug": true], source: "Test Bench")
        return "Recorded test_bench_action"
    }

    /// Makes two objects that each hold themselves, so neither deallocates. Their class allows one
    /// live instance, so Leaks lists it with a count of two (more with each press).
    static func leakRetainCycles() async -> String {
        for _ in 0 ..< 2 {
            TestBenchLeakedObject().holdItself()
        }
        return "Leaked two TestBenchLeakedObject"
    }

    /// Blocks the main thread for two seconds with `Thread.sleep`: the stall itself is what this
    /// action is for, so Hangs reports it with its stack.
    static func hangMainThread() async -> String {
        blockMainThread(seconds: 2)
        return "Blocked the main thread for 2 s"
    }

    /// Synchronous, so the sleep holds the main thread rather than suspending a task, which is
    /// what Swift's async rules steer `Thread.sleep` away from and what this action wants.
    private static func blockMainThread(seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    /// Ends the app with a Swift runtime failure; Crash Reports shows it on the next launch.
    static func crash() async -> String {
        fatalError("The test bench's Crash the App was used")
    }
}

/// An object that opts in to lifetime tracking, one allowed at a time, and can be made to leak.
final class TestBenchLeakedObject {
    private var cycle: TestBenchLeakedObject?

    init() {
        LeakDetector.trackLifetime(of: self)
    }

    /// The deliberate leak: the object holds a strong reference to itself.
    func holdItself() {
        cycle = self
    }
}
