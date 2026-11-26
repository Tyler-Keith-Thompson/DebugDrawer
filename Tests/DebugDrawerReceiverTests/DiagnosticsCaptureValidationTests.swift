// What a diagnostics capture's redaction and limits refuse as they are made, rather than let
// through what a rule was meant to mask or keep nothing. Real in every build, so these run in
// debug and release alike.
import DebugDrawerReceiver
import Testing

@Suite
struct DiagnosticsCaptureValidationTests {
    @Test("A value pattern that isn't a regular expression throws InvalidPattern")
    func invalidPattern() {
        #expect(throws: DebugDrawerDiagnosticsRedaction.InvalidPattern.self) {
            _ = try DebugDrawerDiagnosticsRedaction(values: ["(unclosed"])
        }
    }

    @Test("Adding a value pattern that isn't a regular expression throws InvalidPattern")
    func invalidAddedPattern() {
        #expect(throws: DebugDrawerDiagnosticsRedaction.InvalidPattern.self) {
            _ = try DebugDrawerDiagnosticsRedaction.standard.adding(values: ["[z-a]"])
        }
    }

    @Test("One invalid pattern among valid ones throws InvalidPattern, so no rule is dropped quietly")
    func invalidPatternAmongValidOnes() {
        #expect(throws: DebugDrawerDiagnosticsRedaction.InvalidPattern.self) {
            _ = try DebugDrawerDiagnosticsRedaction(values: [#"\bACCT-\d{6}\b"#, "(unclosed"])
        }
    }

    @Test("Rules with no value pattern are taken and mask no text")
    func noValuePatterns() throws {
        let expected = "jane@example.com"

        let sut = try DebugDrawerDiagnosticsRedaction()

        #expect(sut.redacting(text: expected) == expected)
    }

    @Test("The standard rules compile every value pattern they list")
    func standardPatternsCompile() throws {
        let expected = DebugDrawerDiagnosticsRedaction.standard

        let actual = try DebugDrawerDiagnosticsRedaction(
            headers: expected.headerNames, keys: expected.keyPatterns, jsonPaths: expected.jsonPaths, values: expected.valuePatterns
        )

        #expect(actual == expected)
        #expect(actual.redacting(text: "Bearer abc.def") == expected.redacting(text: "Bearer abc.def"))
    }

    @Test("Limits that keep no line throw noLines")
    func noLines() {
        let expected = DebugDrawerDiagnosticsCapture.InvalidLimits.noLines

        #expect(throws: expected) {
            _ = try DebugDrawerDiagnosticsCapture.Limits(lines: 0, requests: 1, bodyBytes: 0, totalBytes: 1)
        }
    }

    @Test("Limits that keep no request throw noRequests")
    func noRequests() {
        let expected = DebugDrawerDiagnosticsCapture.InvalidLimits.noRequests

        #expect(throws: expected) {
            _ = try DebugDrawerDiagnosticsCapture.Limits(lines: 1, requests: 0, bodyBytes: 0, totalBytes: 1)
        }
    }

    @Test("Limits with a negative body size throw negativeBodyBytes")
    func negativeBodyBytes() {
        let expected = DebugDrawerDiagnosticsCapture.InvalidLimits.negativeBodyBytes

        #expect(throws: expected) {
            _ = try DebugDrawerDiagnosticsCapture.Limits(lines: 1, requests: 1, bodyBytes: -1, totalBytes: 1)
        }
    }

    @Test("Limits that keep no byte in all throw noTotalBytes")
    func noTotalBytes() {
        let expected = DebugDrawerDiagnosticsCapture.InvalidLimits.noTotalBytes

        #expect(throws: expected) {
            _ = try DebugDrawerDiagnosticsCapture.Limits(lines: 1, requests: 1, bodyBytes: 0, totalBytes: 0)
        }
    }

    @Test("Limits of one line, one request, no body and one byte are taken: the edge of the valid range")
    func smallestLimits() throws {
        let expectedLines = 1
        let expectedRequests = 1
        let expectedBodyBytes = 0
        let expectedTotalBytes = 1

        let actual = try DebugDrawerDiagnosticsCapture.Limits(
            lines: expectedLines, requests: expectedRequests, bodyBytes: expectedBodyBytes, totalBytes: expectedTotalBytes
        )

        #expect(actual.lines == expectedLines)
        #expect(actual.requests == expectedRequests)
        #expect(actual.bodyBytes == expectedBodyBytes)
        #expect(actual.totalBytes == expectedTotalBytes)
    }

    @Test("The standard limits keep 1,000 lines, 200 requests, 64 KiB bodies and 2 MiB in all")
    func standardLimits() {
        let expectedLines = 1000
        let expectedRequests = 200
        let expectedBodyBytes = 64 << 10
        let expectedTotalBytes = 2 << 20

        let actual = DebugDrawerDiagnosticsCapture.Limits.standard

        #expect(actual.lines == expectedLines)
        #expect(actual.requests == expectedRequests)
        #expect(actual.bodyBytes == expectedBodyBytes)
        #expect(actual.totalBytes == expectedTotalBytes)
    }
}
