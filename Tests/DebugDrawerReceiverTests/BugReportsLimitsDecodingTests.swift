// What decoding bug reports' limits refuses: the bounds their throwing initializer refuses, so a
// snapshot read from a file or a sidecar can't carry limits no host could make. Real in every
// build, so these run in debug and release alike.
import DebugDrawerReceiver
import Foundation
import Testing

@Suite
struct BugReportsLimitsDecodingTests {
    @Test("Decoding limits that keep no report throws dataCorrupted whose underlying error is noReports")
    func decodingNoReports() throws {
        let expected = DebugDrawerBugReports.InvalidLimits.noReports
        let json = Data(#"{"reports":0,"logLines":0,"stateBytes":0,"screenshotBytes":0}"#.utf8)

        let error = try #require(throws: DecodingError.self) {
            try JSONDecoder().decode(DebugDrawerBugReports.Limits.self, from: json)
        }

        guard case .dataCorrupted(let context) = error else {
            Issue.record("Expected dataCorrupted, got \(error)")
            return
        }
        let actual = context.underlyingError as? DebugDrawerBugReports.InvalidLimits
        #expect(actual == expected)
    }

    @Test("Decoding limits copying a negative number of log lines throws dataCorrupted whose underlying error is negativeLogLines")
    func decodingNegativeLogLines() throws {
        let expected = DebugDrawerBugReports.InvalidLimits.negativeLogLines
        let json = Data(#"{"reports":1,"logLines":-1,"stateBytes":0,"screenshotBytes":0}"#.utf8)

        let error = try #require(throws: DecodingError.self) {
            try JSONDecoder().decode(DebugDrawerBugReports.Limits.self, from: json)
        }

        guard case .dataCorrupted(let context) = error else {
            Issue.record("Expected dataCorrupted, got \(error)")
            return
        }
        let actual = context.underlyingError as? DebugDrawerBugReports.InvalidLimits
        #expect(actual == expected)
    }

    @Test("Decoding limits with a negative state size throws dataCorrupted whose underlying error is negativeStateBytes")
    func decodingNegativeStateBytes() throws {
        let expected = DebugDrawerBugReports.InvalidLimits.negativeStateBytes
        let json = Data(#"{"reports":1,"logLines":0,"stateBytes":-1,"screenshotBytes":0}"#.utf8)

        let error = try #require(throws: DecodingError.self) {
            try JSONDecoder().decode(DebugDrawerBugReports.Limits.self, from: json)
        }

        guard case .dataCorrupted(let context) = error else {
            Issue.record("Expected dataCorrupted, got \(error)")
            return
        }
        let actual = context.underlyingError as? DebugDrawerBugReports.InvalidLimits
        #expect(actual == expected)
    }

    @Test("Decoding limits with a negative screenshot size throws dataCorrupted whose underlying error is negativeScreenshotBytes")
    func decodingNegativeScreenshotBytes() throws {
        let expected = DebugDrawerBugReports.InvalidLimits.negativeScreenshotBytes
        let json = Data(#"{"reports":1,"logLines":0,"stateBytes":0,"screenshotBytes":-1}"#.utf8)

        let error = try #require(throws: DecodingError.self) {
            try JSONDecoder().decode(DebugDrawerBugReports.Limits.self, from: json)
        }

        guard case .dataCorrupted(let context) = error else {
            Issue.record("Expected dataCorrupted, got \(error)")
            return
        }
        let actual = context.underlyingError as? DebugDrawerBugReports.InvalidLimits
        #expect(actual == expected)
    }

    @Test("A refused decode carries the coding path of the limits' container")
    func refusedDecodeCodingPath() throws {
        let expected = ["limits"]
        let json = Data(#"{"limits":{"reports":0,"logLines":0,"stateBytes":0,"screenshotBytes":0}}"#.utf8)

        let error = try #require(throws: DecodingError.self) {
            try JSONDecoder().decode([String: DebugDrawerBugReports.Limits].self, from: json)
        }

        guard case .dataCorrupted(let context) = error else {
            Issue.record("Expected dataCorrupted, got \(error)")
            return
        }
        let actual = context.codingPath.map(\.stringValue)
        #expect(actual == expected)
    }

    @Test("Decoding limits at the edge of the valid range gives what the throwing initializer makes")
    func decodingValidLimits() throws {
        let expected = try DebugDrawerBugReports.Limits(reports: 1, logLines: 0, stateBytes: 0, screenshotBytes: 0)
        let json = Data(#"{"reports":1,"logLines":0,"stateBytes":0,"screenshotBytes":0}"#.utf8)

        let actual = try JSONDecoder().decode(DebugDrawerBugReports.Limits.self, from: json)

        #expect(actual == expected)
    }

    @Test("The standard limits encode under their field names and decode to themselves")
    func standardRoundTrips() throws {
        let expected = DebugDrawerBugReports.Limits.standard
        let expectedJSON = #"{"logLines":200,"reports":3,"screenshotBytes":4194304,"stateBytes":65536}"#
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys

        let data = try encoder.encode(expected)
        let actual = try JSONDecoder().decode(DebugDrawerBugReports.Limits.self, from: data)

        #expect(String(bytes: data, encoding: .utf8) == expectedJSON)
        #expect(actual == expected)
    }
}
