// What bug reports' limits refuse as they are made. Real in every build, so these run in debug and
// release alike.
import DebugDrawerReceiver
import Testing

@Suite
struct BugReportsValidationTests {
    @Test("Limits that keep no report throw noReports")
    func noReports() {
        let expected = DebugDrawerBugReports.InvalidLimits.noReports

        #expect(throws: expected) {
            _ = try DebugDrawerBugReports.Limits(reports: 0, logLines: 0, stateBytes: 0, screenshotBytes: 0)
        }
    }

    @Test("Limits copying a negative number of log lines throw negativeLogLines")
    func negativeLogLines() {
        let expected = DebugDrawerBugReports.InvalidLimits.negativeLogLines

        #expect(throws: expected) {
            _ = try DebugDrawerBugReports.Limits(reports: 1, logLines: -1, stateBytes: 0, screenshotBytes: 0)
        }
    }

    @Test("Limits with a negative state size throw negativeStateBytes")
    func negativeStateBytes() {
        let expected = DebugDrawerBugReports.InvalidLimits.negativeStateBytes

        #expect(throws: expected) {
            _ = try DebugDrawerBugReports.Limits(reports: 1, logLines: 0, stateBytes: -1, screenshotBytes: 0)
        }
    }

    @Test("Limits with a negative screenshot size throw negativeScreenshotBytes")
    func negativeScreenshotBytes() {
        let expected = DebugDrawerBugReports.InvalidLimits.negativeScreenshotBytes

        #expect(throws: expected) {
            _ = try DebugDrawerBugReports.Limits(reports: 1, logLines: 0, stateBytes: 0, screenshotBytes: -1)
        }
    }

    @Test("Limits of one report and nothing else kept are taken: the edge of the valid range")
    func smallestLimits() throws {
        let expectedReports = 1
        let expectedSize = 0

        let actual = try DebugDrawerBugReports.Limits(
            reports: expectedReports, logLines: expectedSize, stateBytes: expectedSize, screenshotBytes: expectedSize
        )

        #expect(actual.reports == expectedReports)
        #expect(actual.logLines == expectedSize)
        #expect(actual.stateBytes == expectedSize)
        #expect(actual.screenshotBytes == expectedSize)
    }

    @Test("The standard limits keep 3 reports, 200 log lines, 64 KiB of state and 4 MiB of screenshot")
    func standardLimits() {
        let expectedReports = 3
        let expectedLogLines = 200
        let expectedStateBytes = 64 << 10
        let expectedScreenshotBytes = 4 << 20

        let actual = DebugDrawerBugReports.Limits.standard

        #expect(actual.reports == expectedReports)
        #expect(actual.logLines == expectedLogLines)
        #expect(actual.stateBytes == expectedStateBytes)
        #expect(actual.screenshotBytes == expectedScreenshotBytes)
    }
}
