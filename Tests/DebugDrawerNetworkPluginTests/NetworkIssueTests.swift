// Views render on the Mac; ViewInspector is linked on Apple platforms only.
#if os(macOS)
    @testable import DebugDrawer
    @testable import DebugDrawerNetworkPlugin
    import SwiftUI
    import Testing
    import ViewInspector

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct NetworkIssueTests {
        @Test("A request fails when its status is 400 or more, or when it got no answer; 2xx, 3xx and one in progress don't")
        func failureRule() {
            let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
            let entries = [
                NetworkEntry(timestamp: start, method: "GET", url: "", host: "", path: "", requestHeaders: [:], requestBody: nil,
                             statusCode: 200, isComplete: true),
                NetworkEntry(timestamp: start, method: "GET", url: "", host: "", path: "", requestHeaders: [:], requestBody: nil,
                             statusCode: 304, isComplete: true),
                NetworkEntry(timestamp: start, method: "GET", url: "", host: "", path: "", requestHeaders: [:], requestBody: nil,
                             statusCode: 399, isComplete: true),
                NetworkEntry(timestamp: start, method: "GET", url: "", host: "", path: "", requestHeaders: [:], requestBody: nil,
                             statusCode: 400, isComplete: true),
                NetworkEntry(timestamp: start, method: "GET", url: "", host: "", path: "", requestHeaders: [:], requestBody: nil,
                             statusCode: 503, isComplete: true),
                NetworkEntry(timestamp: start, method: "GET", url: "", host: "", path: "", requestHeaders: [:], requestBody: nil,
                             error: "The network connection was lost.", isComplete: true),
                NetworkEntry(timestamp: start, method: "GET", url: "", host: "", path: "", requestHeaders: [:], requestBody: nil,
                             isComplete: false)
            ]
            let expected = [false, false, false, true, true, true, false]

            let actual = entries.map(\.isFailure)

            #expect(actual == expected)
        }

        @Test("A failed request's row shows the error glyph; a successful one leaves its space empty")
        func rowGlyph() throws {
            let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
            let failed = NetworkEntry(timestamp: start, method: "POST", url: "", host: "", path: "/v1/orders", requestHeaders: [:],
                                      requestBody: nil, statusCode: 422, duration: 1.25, isComplete: true)
            let succeeded = NetworkEntry(timestamp: start, method: "GET", url: "", host: "", path: "/v1/users", requestHeaders: [:],
                                         requestBody: nil, statusCode: 200, duration: 0.142, isComplete: true)
            let failedRow = NetworkRequestRow(entry: failed, redaction: .standard, isSelected: false, onSelect: {})
            let succeededRow = NetworkRequestRow(entry: succeeded, redaction: .standard, isSelected: false, onSelect: {})

            let failedOpacity = try failedRow.inspect().find(DebugDrawerIssueGlyph.self).opacity()
            let succeededOpacity = try succeededRow.inspect().find(DebugDrawerIssueGlyph.self).opacity()
            let status = try failedRow.inspect().find(text: "422").string()

            #expect(failedOpacity == 1)
            #expect(succeededOpacity == 0)
            #expect(status == "422")
        }

        @Test("The header summary counts the requests and, when any failed, shows the error glyph with their count")
        func headerSummary() throws {
            let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
            let entries = [
                NetworkEntry(timestamp: start, method: "GET", url: "", host: "", path: "", requestHeaders: [:], requestBody: nil,
                             statusCode: 200, isComplete: true),
                NetworkEntry(timestamp: start, method: "GET", url: "", host: "", path: "", requestHeaders: [:], requestBody: nil,
                             statusCode: 500, isComplete: true),
                NetworkEntry(timestamp: start, method: "GET", url: "", host: "", path: "", requestHeaders: [:], requestBody: nil,
                             error: "Timed out", isComplete: true)
            ]
            let sut = NetworkHeaderSummary(entries: entries)
            let expectedSummary = "3 requests"
            let expectedFailures = "2 errors"

            let actualSummary = try sut.inspect().find(text: expectedSummary).string()
            let actualFailures = try sut.inspect().find(DebugDrawerIssueCount.self).actualView().spokenLabel

            #expect(actualSummary == expectedSummary)
            #expect(actualFailures == expectedFailures)
        }

        @Test("With no failed request the header summary shows the count alone, one request in the singular")
        func headerSummaryWithoutFailures() throws {
            let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
            let entries = [
                NetworkEntry(timestamp: start, method: "GET", url: "", host: "", path: "", requestHeaders: [:], requestBody: nil,
                             statusCode: 204, isComplete: true)
            ]
            let sut = NetworkHeaderSummary(entries: entries)
            let expected = "1 request"

            let actual = try sut.inspect().find(text: expected).string()

            #expect(actual == expected)
            #expect(throws: (any Error).self) { try sut.inspect().find(DebugDrawerIssueCount.self) }
        }

        @Test("The plugin declares its header accessory")
        func pluginHasAccessory() {
            let sut = AnyDebugDrawerPlugin(NetworkPlugin())

            let actual = sut.headerAccessory

            #expect(actual != nil)
        }
    }
#endif
