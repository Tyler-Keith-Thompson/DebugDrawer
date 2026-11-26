// What decoding a diagnostics capture's limits refuses: the bounds its throwing initializer
// refuses, so a snapshot read from a file or a sidecar can't carry limits no host could make. Real
// in every build, so these run in debug and release alike.
import DebugDrawerReceiver
import Foundation
import Testing

@Suite
struct DiagnosticsCaptureLimitsDecodingTests {
    @Test("Decoding limits that keep no log line throws dataCorrupted whose underlying error is noLines")
    func decodingNoLines() throws {
        let expected = DebugDrawerDiagnosticsCapture.InvalidLimits.noLines
        let json = Data(#"{"lines":0,"requests":1,"bodyBytes":0,"totalBytes":1}"#.utf8)

        let error = try #require(throws: DecodingError.self) {
            try JSONDecoder().decode(DebugDrawerDiagnosticsCapture.Limits.self, from: json)
        }

        guard case .dataCorrupted(let context) = error else {
            Issue.record("Expected dataCorrupted, got \(error)")
            return
        }
        let actual = context.underlyingError as? DebugDrawerDiagnosticsCapture.InvalidLimits
        #expect(actual == expected)
    }

    @Test("Decoding limits that keep no request throws dataCorrupted whose underlying error is noRequests")
    func decodingNoRequests() throws {
        let expected = DebugDrawerDiagnosticsCapture.InvalidLimits.noRequests
        let json = Data(#"{"lines":1,"requests":0,"bodyBytes":0,"totalBytes":1}"#.utf8)

        let error = try #require(throws: DecodingError.self) {
            try JSONDecoder().decode(DebugDrawerDiagnosticsCapture.Limits.self, from: json)
        }

        guard case .dataCorrupted(let context) = error else {
            Issue.record("Expected dataCorrupted, got \(error)")
            return
        }
        let actual = context.underlyingError as? DebugDrawerDiagnosticsCapture.InvalidLimits
        #expect(actual == expected)
    }

    @Test("Decoding limits with a negative body size throws dataCorrupted whose underlying error is negativeBodyBytes")
    func decodingNegativeBodyBytes() throws {
        let expected = DebugDrawerDiagnosticsCapture.InvalidLimits.negativeBodyBytes
        let json = Data(#"{"lines":1,"requests":1,"bodyBytes":-1,"totalBytes":1}"#.utf8)

        let error = try #require(throws: DecodingError.self) {
            try JSONDecoder().decode(DebugDrawerDiagnosticsCapture.Limits.self, from: json)
        }

        guard case .dataCorrupted(let context) = error else {
            Issue.record("Expected dataCorrupted, got \(error)")
            return
        }
        let actual = context.underlyingError as? DebugDrawerDiagnosticsCapture.InvalidLimits
        #expect(actual == expected)
    }

    @Test("Decoding limits that keep no byte in all throws dataCorrupted whose underlying error is noTotalBytes")
    func decodingNoTotalBytes() throws {
        let expected = DebugDrawerDiagnosticsCapture.InvalidLimits.noTotalBytes
        let json = Data(#"{"lines":1,"requests":1,"bodyBytes":0,"totalBytes":0}"#.utf8)

        let error = try #require(throws: DecodingError.self) {
            try JSONDecoder().decode(DebugDrawerDiagnosticsCapture.Limits.self, from: json)
        }

        guard case .dataCorrupted(let context) = error else {
            Issue.record("Expected dataCorrupted, got \(error)")
            return
        }
        let actual = context.underlyingError as? DebugDrawerDiagnosticsCapture.InvalidLimits
        #expect(actual == expected)
    }

    @Test("A refused decode carries the coding path of the limits' container")
    func refusedDecodeCodingPath() throws {
        let expected = ["limits"]
        let json = Data(#"{"limits":{"lines":0,"requests":1,"bodyBytes":0,"totalBytes":1}}"#.utf8)

        let error = try #require(throws: DecodingError.self) {
            try JSONDecoder().decode([String: DebugDrawerDiagnosticsCapture.Limits].self, from: json)
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
        let expected = try DebugDrawerDiagnosticsCapture.Limits(lines: 1, requests: 1, bodyBytes: 0, totalBytes: 1)
        let json = Data(#"{"lines":1,"requests":1,"bodyBytes":0,"totalBytes":1}"#.utf8)

        let actual = try JSONDecoder().decode(DebugDrawerDiagnosticsCapture.Limits.self, from: json)

        #expect(actual == expected)
    }

    @Test("The standard limits encode under their field names and decode to themselves")
    func standardRoundTrips() throws {
        let expected = DebugDrawerDiagnosticsCapture.Limits.standard
        let expectedJSON = #"{"bodyBytes":65536,"lines":1000,"requests":200,"totalBytes":2097152}"#
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys

        let data = try encoder.encode(expected)
        let actual = try JSONDecoder().decode(DebugDrawerDiagnosticsCapture.Limits.self, from: data)

        #expect(String(bytes: data, encoding: .utf8) == expectedJSON)
        #expect(actual == expected)
    }
}
