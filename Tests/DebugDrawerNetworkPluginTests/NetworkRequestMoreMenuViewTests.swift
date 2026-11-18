// ViewInspector is linked on Apple platforms only, and the views are tested on the Mac.
#if os(macOS)
    @testable import DebugDrawer
    @testable import DebugDrawerNetworkPlugin
    import Foundation
    import SwiftUI
    import Testing
    import ViewInspector

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct NetworkRequestMoreMenuViewTests {
        @Test("More offers Copy cURL, Mock This, Edit and Resend… and Ignore Host, and each calls its action once")
        func eachActionFires() throws {
            final class Calls {
                var copies = 0
                var mocks = 0
                var edits = 0
                var ignored: [String] = []
            }
            let calls = Calls()
            let sut = NetworkRequestMoreMenu(
                copyCURL: { calls.copies += 1 },
                mock: { calls.mocks += 1 },
                editAndResend: { calls.edits += 1 },
                host: "cdn.example.com",
                ignore: { calls.ignored.append($0.name) }
            )
            let expectedIgnored = ["example.com"]

            let menu = try sut.inspect().find(ViewType.Menu.self) { try $0.accessibilityLabel().string() == "More" }
            try menu.find(button: "Copy cURL").tap()
            try menu.find(button: "Mock This").tap()
            try menu.find(button: "Edit and Resend…").tap()
            try menu.find(button: "Ignore example.com").tap()

            #expect(calls.copies == 1)
            #expect(calls.mocks == 1)
            #expect(calls.edits == 1)
            #expect(calls.ignored == expectedIgnored)
        }

        @Test("Each action in More keeps its accessibility label and hint")
        func accessibility() throws {
            let sut = NetworkRequestMoreMenu(copyCURL: {}, mock: {}, editAndResend: {}, host: "cdn.example.com", ignore: { _ in })
            let expectedLabels = ["Copy cURL", "Mock This", "Edit and Resend…", "Ignore Host", "More"]
            let expectedHints = [
                "Copies to the clipboard",
                "Makes a mock that answers requests like this one with its response",
                "Opens the request to change its method, URL, headers or body before sending it again",
                "Hides the requests to this host, and its subdomains, from the log"
            ]

            let view = try sut.inspect()
            let copy = try view.find(button: "Copy cURL")
            let mock = try view.find(button: "Mock This")
            let edit = try view.find(button: "Edit and Resend…")
            let ignore = try view.find(ViewType.Menu.self) { try $0.accessibilityLabel().string() == "Ignore Host" }
            let more = try view.find(ViewType.Menu.self) { try $0.accessibilityLabel().string() == "More" }
            let labels = try [copy, mock, edit].map { try $0.accessibilityLabel().string() }
                + [ignore.accessibilityLabel().string(), more.accessibilityLabel().string()]
            let hints = try [copy.accessibilityHint(), mock.accessibilityHint(), edit.accessibilityHint(), ignore.accessibilityHint()]
                .map { try $0.string() }

            #expect(labels == expectedLabels)
            #expect(hints == expectedHints)
        }

        @Test("Without its actions More offers Copy cURL alone")
        func copyOnly() throws {
            let sut = NetworkRequestMoreMenu(copyCURL: {})
            let expected = ["Copy cURL"]

            let actual = try sut.inspect().findAll(ViewType.Button.self).map { try $0.labelView().text().string() }

            #expect(actual == expected)
        }

        @Test("A request's detail hands Mock This, Edit and Resend… and Ignore the request through More")
        func detailRoutesThroughMore() throws {
            let entry = NetworkEntry(
                timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000), method: "GET", url: "https://api.example.com/v1/orders",
                host: "api.example.com", path: "/v1/orders", requestHeaders: [:], requestBody: nil, statusCode: 200, isComplete: true
            )
            final class Calls {
                var mocked: [UUID] = []
                var edited: [UUID] = []
                var ignored: [String] = []
            }
            let calls = Calls()
            let sut = NetworkRequestDetail(
                entry: entry,
                redaction: .standard,
                onMock: { calls.mocked.append($0.id) },
                onResend: { _ in },
                onEditAndResend: { calls.edited.append($0.id) },
                onIgnore: { calls.ignored.append($0.name) }
            )
            let expectedIgnored = ["example.com"]

            let more = try sut.inspect().find(NetworkRequestMoreMenu.self)
            try more.find(button: "Mock This").tap()
            try more.find(button: "Edit and Resend…").tap()
            try more.find(button: "Ignore example.com").tap()

            #expect(calls.mocked == [entry.id])
            #expect(calls.edited == [entry.id])
            #expect(calls.ignored == expectedIgnored)
        }
    }
#endif
