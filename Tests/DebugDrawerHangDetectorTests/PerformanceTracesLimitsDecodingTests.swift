// What decoding a recording's limits refuses: the bounds its throwing initializer refuses, so a
// snapshot read from a file or a sidecar can't carry limits no host could make. Real in every
// build, so these run in debug and release alike.
import DebugDrawerHangDetector
import Foundation
import Testing

@Suite
struct PerformanceTracesLimitsDecodingTests {
    @Test("Decoding limits that keep no stall throws dataCorrupted whose underlying error is noStalls")
    func decodingNoStalls() throws {
        let expected = PerformanceTraces.InvalidLimits.noStalls
        let json = Data(#"{"stalls":0,"intervals":1}"#.utf8)

        let error = try #require(throws: DecodingError.self) {
            try JSONDecoder().decode(PerformanceTraces.Limits.self, from: json)
        }

        guard case .dataCorrupted(let context) = error else {
            Issue.record("Expected dataCorrupted, got \(error)")
            return
        }
        let actual = context.underlyingError as? PerformanceTraces.InvalidLimits
        #expect(actual == expected)
    }

    @Test("Decoding limits that keep no interval throws dataCorrupted whose underlying error is noIntervals")
    func decodingNoIntervals() throws {
        let expected = PerformanceTraces.InvalidLimits.noIntervals
        let json = Data(#"{"stalls":1,"intervals":0}"#.utf8)

        let error = try #require(throws: DecodingError.self) {
            try JSONDecoder().decode(PerformanceTraces.Limits.self, from: json)
        }

        guard case .dataCorrupted(let context) = error else {
            Issue.record("Expected dataCorrupted, got \(error)")
            return
        }
        let actual = context.underlyingError as? PerformanceTraces.InvalidLimits
        #expect(actual == expected)
    }

    @Test("A refused decode carries the coding path of the limits' container")
    func refusedDecodeCodingPath() throws {
        let expected = ["limits"]
        let json = Data(#"{"limits":{"stalls":0,"intervals":1}}"#.utf8)

        let error = try #require(throws: DecodingError.self) {
            try JSONDecoder().decode([String: PerformanceTraces.Limits].self, from: json)
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
        let expected = try PerformanceTraces.Limits(stalls: 1, intervals: 1)
        let json = Data(#"{"stalls":1,"intervals":1}"#.utf8)

        let actual = try JSONDecoder().decode(PerformanceTraces.Limits.self, from: json)

        #expect(actual == expected)
    }

    @Test("The standard limits encode under their field names and decode to themselves")
    func standardRoundTrips() throws {
        let expected = PerformanceTraces.Limits.standard
        let expectedJSON = #"{"intervals":500,"stalls":50}"#
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys

        let data = try encoder.encode(expected)
        let actual = try JSONDecoder().decode(PerformanceTraces.Limits.self, from: data)

        #expect(String(bytes: data, encoding: .utf8) == expectedJSON)
        #expect(actual == expected)
    }
}
