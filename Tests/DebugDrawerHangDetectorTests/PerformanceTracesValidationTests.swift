// What a recorder refuses as it is made: thresholds and limits it couldn't record with. Real in
// every build, so these run in debug and release alike.
import DebugDrawerHangDetector
import DebugDrawerReceiver
import Testing

@MainActor
@Suite
struct PerformanceTracesValidationTests {
    @Test("A hitch threshold of 0 throws hitchThresholdNotPositive")
    func zeroHitchThreshold() {
        let expected = PerformanceTraces.InvalidThresholds.hitchThresholdNotPositive

        #expect(throws: expected) {
            _ = try PerformanceTraces(sessions: DebugDrawerSessions(maximumDuration: 60), hitchThreshold: .zero)
        }
    }

    @Test("A negative hitch threshold throws hitchThresholdNotPositive")
    func negativeHitchThreshold() {
        let expected = PerformanceTraces.InvalidThresholds.hitchThresholdNotPositive

        #expect(throws: expected) {
            _ = try PerformanceTraces(sessions: DebugDrawerSessions(maximumDuration: 60), hitchThreshold: .milliseconds(-1))
        }
    }

    @Test("A hitch threshold longer than the hang threshold throws hitchThresholdAboveHangThreshold")
    func hitchAboveHang() {
        let expected = PerformanceTraces.InvalidThresholds.hitchThresholdAboveHangThreshold
        let hitch: Duration = .milliseconds(300)
        let hang: Duration = .milliseconds(250)

        #expect(throws: expected) {
            _ = try PerformanceTraces(sessions: DebugDrawerSessions(maximumDuration: 60), hitchThreshold: hitch, hangThreshold: hang)
        }
    }

    @Test("A hitch threshold equal to the hang threshold is taken: the edge of the valid range")
    func hitchEqualToHang() throws {
        let expected: Duration = .milliseconds(250)

        let sut = try PerformanceTraces(sessions: DebugDrawerSessions(maximumDuration: 60), hitchThreshold: expected, hangThreshold: expected)

        #expect(sut.snapshot.hitchThreshold == expected)
        #expect(sut.snapshot.hangThreshold == expected)
    }

    @Test("Limits that keep no stall throw noStalls")
    func noStalls() {
        let expected = PerformanceTraces.InvalidLimits.noStalls

        #expect(throws: expected) {
            _ = try PerformanceTraces.Limits(stalls: 0, intervals: 1)
        }
    }

    @Test("Limits that keep no interval throw noIntervals")
    func noIntervals() {
        let expected = PerformanceTraces.InvalidLimits.noIntervals

        #expect(throws: expected) {
            _ = try PerformanceTraces.Limits(stalls: 1, intervals: 0)
        }
    }

    @Test("Limits of one stall and one interval are taken: the edge of the valid range")
    func smallestLimits() throws {
        let expectedStalls = 1
        let expectedIntervals = 1

        let actual = try PerformanceTraces.Limits(stalls: expectedStalls, intervals: expectedIntervals)

        #expect(actual.stalls == expectedStalls)
        #expect(actual.intervals == expectedIntervals)
    }

    @Test("The standard limits keep 50 stalls and 500 intervals")
    func standardLimits() {
        let expectedStalls = 50
        let expectedIntervals = 500

        let actual = PerformanceTraces.Limits.standard

        #expect(actual.stalls == expectedStalls)
        #expect(actual.intervals == expectedIntervals)
    }
}
