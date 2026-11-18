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
    struct NetworkIgnoreViewTests {
        @Test("A request to a host with parent domains offers each in Ignore Host; choosing example.com ignores example.com")
        func ignoreParentDomainFromDetail() throws {
            let entry = NetworkEntry(
                timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000), method: "GET", url: "https://cdn.img.example.com/a.png",
                host: "cdn.img.example.com", path: "/a.png", requestHeaders: [:], requestBody: nil, statusCode: 200, isComplete: true
            )
            var ignored: [String] = []
            let sut = NetworkRequestDetail(entry: entry, redaction: .standard, onIgnore: { ignored.append($0.name) })

            let menu = try sut.inspect().find(ViewType.Menu.self) { try $0.accessibilityLabel().string() == "Ignore Host" }
            let choices = try menu.findAll(ViewType.Button.self).map { try $0.labelView().text().string() }
            try menu.find(button: "Ignore example.com").tap()

            #expect(choices == ["Ignore cdn.img.example.com", "Ignore img.example.com", "Ignore example.com"])
            #expect(ignored == ["example.com"])
        }

        @Test("A request to a two-label host or an address offers one Ignore button, which ignores that host")
        func ignoreSingleChoiceFromDetail() throws {
            let entry = NetworkEntry(
                timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000), method: "GET", url: "http://10.0.0.1:8080/health",
                host: "10.0.0.1", path: "/health", requestHeaders: [:], requestBody: nil, statusCode: 200, isComplete: true
            )
            var ignored: [String] = []
            let sut = NetworkRequestDetail(entry: entry, redaction: .standard, onIgnore: { ignored.append($0.name) })

            try sut.inspect().find(button: "Ignore 10.0.0.1").tap()

            #expect((try? sut.inspect().find(ViewType.Menu.self) { try $0.accessibilityLabel().string() == "Ignore Host" }) == nil)
            #expect(ignored == ["10.0.0.1"])
        }

        @Test("With no ignore action, as for a host already ignored, the detail offers no Ignore")
        func noIgnoreWithoutAction() throws {
            let entry = NetworkEntry(
                timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000), method: "GET", url: "https://example.com/",
                host: "example.com", path: "/", requestHeaders: [:], requestBody: nil, statusCode: 200, isComplete: true
            )
            let sut = NetworkRequestDetail(entry: entry, redaction: .standard)

            let actual = try? sut.inspect().find(button: "Ignore example.com")

            #expect(actual == nil)
        }

        @Test("A POST with operationName GetUser shows GetUser in its row, under its path, and Operation GetUser in its detail")
        func graphQLOperationShown() throws {
            let entry = NetworkEntry(
                timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000), method: "POST", url: "https://api.example.com/graphql",
                host: "api.example.com", path: "/graphql", requestHeaders: [:], requestBody: Data(#"{"operationName":"GetUser"}"#.utf8),
                statusCode: 200, isComplete: true
            )
            let detail = NetworkRequestDetail(entry: entry, redaction: .standard)
            let row = NetworkRequestRow(entry: entry, redaction: .standard, isSelected: false, onSelect: {})

            let label = try detail.inspect().find(text: "Operation").string()
            let value = try detail.inspect().find(text: "GetUser").string()
            let rowTexts = try row.inspect().findAll(ViewType.Text.self).map { try $0.string() }

            #expect(label == "Operation")
            #expect(value == "GetUser")
            #expect(rowTexts.contains("/graphql"))
            #expect(rowTexts.contains("GetUser"))
        }

        @Test("The hint says how many the list hides, Show calls back, and while shown it says so with Hide")
        func hint() throws {
            var toggles = 0
            let hidden = NetworkIgnoredHint(count: 12, isShowing: false) { toggles += 1 }
            let shown = NetworkIgnoredHint(count: 1, isShowing: true) { toggles += 1 }

            let hiddenTitle = try hidden.inspect().find(text: "12 hidden by ignore list").string()
            try hidden.inspect().find(button: "Show").tap()
            let shownTitle = try shown.inspect().find(text: "1 from ignored hosts shown").string()
            try shown.inspect().find(button: "Hide").tap()

            #expect(hiddenTitle == "12 hidden by ignore list")
            #expect(shownTitle == "1 from ignored hosts shown")
            #expect(toggles == 2)
        }

        @Test("With nothing ignored among the requests shown, the hint shows nothing")
        func hintHiddenAtZero() throws {
            let sut = NetworkIgnoredHint(count: 0, isShowing: false) {}

            let actual = try? sut.inspect().find(button: "Show")

            #expect(actual == nil)
        }

        @Test("Typing a host and Ignore Host adds it, normalized, and empties the field")
        func addTypedHost() async throws {
            var added: [String] = []
            let sut = NetworkIgnoreListSection(domains: [], issue: nil, add: { added.append($0.name) }, remove: { _ in })
            var textAfter = "unread"

            try await ViewHosting.host(sut) {
                try await sut.inspection.inspect { view in
                    try view.find(ViewType.TextField.self).setInput("https://Analytics.Example.net:443/collect")
                }
                try await sut.inspection.inspect { view in
                    try view.find(button: "Ignore Host").tap()
                }
                try await sut.inspection.inspect { view in
                    textAfter = try view.find(ViewType.TextField.self).input()
                }
            }

            #expect(added == ["analytics.example.net"])
            #expect(textAfter.isEmpty)
        }

        @Test("Typed text that isn't a host adds nothing and says why under the field", arguments: [
            ("*.example.com", "Leave out the *: example.com covers its subdomains too."),
            ("not a host", "Not a host: use letters, digits, hyphens and dots, such as cdn.example.com, or an IP address.")
        ])
        func invalidTypedHost(text: String, expected: String) async throws {
            var added: [String] = []
            let sut = NetworkIgnoreListSection(domains: [], issue: nil, add: { added.append($0.name) }, remove: { _ in })
            var problem = ""

            try await ViewHosting.host(sut) {
                try await sut.inspection.inspect { view in
                    try view.find(ViewType.TextField.self).setInput(text)
                }
                try await sut.inspection.inspect { view in
                    try view.find(button: "Ignore Host").tap()
                }
                try await sut.inspection.inspect { view in
                    problem = try view.find(text: expected).string()
                }
            }

            #expect(added.isEmpty)
            #expect(problem == expected)
        }

        @Test("Each ignored domain is listed with Remove, which removes that one")
        func removeDomain() throws {
            let domains = try ["analytics.example.net", "cdn.example.com"].map { try NetworkIgnoredDomain(parsing: $0) }
            var removed: [String] = []
            let sut = NetworkIgnoreListSection(domains: domains, issue: nil, add: { _ in }, remove: { removed.append($0.name) })

            let removeButtons = try sut.inspect().findAll(ViewType.Button.self) { try $0.labelView().text().string() == "Remove" }
            // Every text, without the field's placeholder and the footer.
            let names = try sut.inspect().findAll(ViewType.Text.self).map { try $0.string() }.filter { Set(domains.map(\.name)).contains($0) }
            try sut.inspect().find(viewWithAccessibilityLabel: "Remove cdn.example.com").button().tap()

            #expect(removeButtons.count == 2)
            #expect(names == ["analytics.example.net", "cdn.example.com"])
            #expect(removed == ["cdn.example.com"])
        }

        @Test("A list that couldn't be saved says so above the domains")
        func issueShown() throws {
            let sut = NetworkIgnoreListSection(domains: [], issue: .notSaved, add: { _ in }, remove: { _ in })

            let actual = try sut.inspect().find(text: "The last change couldn't be saved; it lasts until the app quits.").string()

            #expect(actual == "The last change couldn't be saved; it lasts until the app quits.")
        }
    }
#endif
