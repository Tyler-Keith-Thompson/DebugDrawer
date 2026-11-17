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
    struct NetworkReplayViewTests {
        @Test("Resending a POST asks first: nothing is sent until Send in the question, which sends it once")
        func postAsksFirst() async throws {
            let entry = NetworkEntry(
                timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000), method: "POST", url: "https://api.example.com/v1/orders",
                host: "api.example.com", path: "/v1/orders", requestHeaders: [:], requestBody: Data("{}".utf8), statusCode: 201, isComplete: true
            )
            var resent: [UUID] = []
            let sut = NetworkRequestDetail(entry: entry, redaction: .standard, onResend: { resent.append($0.id) })
            var questionBefore = true
            var question = ""
            var sentBeforeConfirming: [UUID] = []

            try await ViewHosting.host(sut) {
                try await sut.inspection.inspect { view in
                    questionBefore = (try? view.find(NetworkResendConfirmation.self)) != nil
                    try view.find(button: "Resend").tap()
                }
                try await sut.inspection.inspect { view in
                    question = try view.find(NetworkResendConfirmation.self).find(text: "Send this POST again?").string()
                    sentBeforeConfirming = resent
                    try view.find(button: "Send").tap()
                }
            }

            #expect(!questionBefore)
            #expect(question == "Send this POST again?")
            #expect(sentBeforeConfirming.isEmpty)
            #expect(resent == [entry.id])
        }

        @Test("Cancelling the question sends nothing and closes it", arguments: ["PUT", "PATCH", "DELETE"])
        func cancelSendsNothing(method: String) async throws {
            let entry = NetworkEntry(
                timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000), method: method, url: "https://api.example.com/v1/orders/1",
                host: "api.example.com", path: "/v1/orders/1", requestHeaders: [:], requestBody: nil, statusCode: 200, isComplete: true
            )
            var resent: [UUID] = []
            let sut = NetworkRequestDetail(entry: entry, redaction: .standard, onResend: { resent.append($0.id) })
            var questionOpen = false
            var questionAfter = true

            try await ViewHosting.host(sut) {
                try await sut.inspection.inspect { view in
                    try view.find(button: "Resend").tap()
                }
                try await sut.inspection.inspect { view in
                    questionOpen = (try? view.find(NetworkResendConfirmation.self)) != nil
                    try view.find(button: "Cancel").tap()
                }
                try await sut.inspection.inspect { view in
                    questionAfter = (try? view.find(NetworkResendConfirmation.self)) != nil
                }
            }

            #expect(questionOpen)
            #expect(!questionAfter)
            #expect(resent.isEmpty)
        }

        @Test("Resending a GET, HEAD or OPTIONS sends at once, with no question", arguments: ["GET", "HEAD", "OPTIONS"])
        func safeSendsAtOnce(method: String) throws {
            let entry = NetworkEntry(
                timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000), method: method, url: "https://example.com/",
                host: "example.com", path: "/", requestHeaders: [:], requestBody: nil, statusCode: 200, isComplete: true
            )
            var resent: [UUID] = []
            let sut = NetworkRequestDetail(entry: entry, redaction: .standard, onResend: { resent.append($0.id) })

            try sut.inspect().find(button: "Resend").tap()

            #expect(resent == [entry.id])
            #expect(throws: (any Error).self) { try sut.inspect().find(NetworkResendConfirmation.self) }
        }

        @Test("Edit and Resend hands over the request; a detail without the actions offers neither")
        func editAndResendAction() throws {
            let entry = NetworkEntry(
                timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000), method: "GET", url: "https://example.com/",
                host: "example.com", path: "/", requestHeaders: [:], requestBody: nil, statusCode: 200, isComplete: true
            )
            var edited: [UUID] = []
            let sut = NetworkRequestDetail(entry: entry, redaction: .standard, onResend: { _ in }, onEditAndResend: { edited.append($0.id) })
            let bare = NetworkRequestDetail(entry: entry, redaction: .standard)

            try sut.inspect().find(button: "Edit and Resend…").tap()

            #expect(edited == [entry.id])
            #expect(throws: (any Error).self) { try bare.inspect().find(button: "Resend") }
            #expect(throws: (any Error).self) { try bare.inspect().find(button: "Edit and Resend…") }
        }

        @Test("A replay shows Replay in its row and, in its detail, the original's method, path and time, whose Show selects it")
        func replayLinksToOriginal() throws {
            let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
            let original = NetworkEntry(
                timestamp: start, method: "GET", url: "https://api.example.com/v1/greeting", host: "api.example.com",
                path: "/v1/greeting", requestHeaders: [:], requestBody: nil, statusCode: 200, isComplete: true
            )
            let replay = NetworkEntry(
                timestamp: start + 5, method: "GET", url: original.url, host: original.host, path: original.path,
                requestHeaders: [:], requestBody: nil, statusCode: 200, isComplete: true, replayOf: original.id
            )
            var shown: [UUID] = []
            let sut = NetworkRequestRow(
                entry: replay, redaction: .standard, isSelected: true, onSelect: {}, onShow: { shown.append($0) },
                links: NetworkReplayLinks(of: replay, in: [replay, original])
            )
            let plain = NetworkRequestRow(entry: original, redaction: .standard, isSelected: false, onSelect: {})
            let shownIn = sut.environment(\.locale, Locale(identifier: "en_US")).environment(\.timeZone, TimeZone(identifier: "UTC") ?? .gmt)
            let expected = "GET /v1/greeting at 6:13:20\u{202F}AM"

            let badge = try shownIn.inspect().find(NetworkReplayBadge.self).find(text: "Replay").string()
            let link = try shownIn.inspect().find(NetworkReplayLinkRows.self).find(DebugDrawerKeyValueRow.self).actualView().value
            try shownIn.inspect().find(button: "Show").tap()

            #expect(badge == "Replay")
            #expect(link == expected)
            #expect(shown == [original.id])
            #expect(throws: (any Error).self) { try plain.inspect().find(NetworkReplayBadge.self) }
        }

        @Test("A resent request says how often, and Show selects the latest replay")
        func originalCountsReplays() throws {
            let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
            let original = NetworkEntry(
                timestamp: start, method: "GET", url: "https://example.com/", host: "example.com", path: "/",
                requestHeaders: [:], requestBody: nil, statusCode: 200, isComplete: true
            )
            let first = NetworkEntry(
                timestamp: start + 1, method: "GET", url: original.url, host: original.host, path: "/",
                requestHeaders: [:], requestBody: nil, statusCode: 200, isComplete: true, replayOf: original.id
            )
            let second = NetworkEntry(
                timestamp: start + 2, method: "GET", url: original.url, host: original.host, path: "/",
                requestHeaders: [:], requestBody: nil, statusCode: 200, isComplete: true, replayOf: original.id
            )
            var shown: [UUID] = []
            let sut = NetworkRequestDetail(
                entry: original, redaction: .standard, onShow: { shown.append($0) },
                links: NetworkReplayLinks(of: original, in: [second, first, original])
            )
            let once = NetworkRequestDetail(entry: original, redaction: .standard, links: NetworkReplayLinks(of: original, in: [first, original]))

            let count = try sut.inspect().find(DebugDrawerKeyValueRow.self, where: { try $0.actualView().label == "Replayed" }).actualView().value
            let countOnce = try once.inspect()
                .find(DebugDrawerKeyValueRow.self, where: { try $0.actualView().label == "Replayed" }).actualView().value
            try sut.inspect().find(button: "Show").tap()

            #expect(count == "2 times")
            #expect(countOnce == "Once")
            #expect(shown == [second.id])
        }

        @Test("A replay whose original left the log says so, with nothing to show")
        func originalGone() throws {
            let replay = NetworkEntry(
                timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000), method: "GET", url: "https://example.com/",
                host: "example.com", path: "/", requestHeaders: [:], requestBody: nil, statusCode: 200, isComplete: true, replayOf: UUID()
            )
            let sut = NetworkRequestDetail(entry: replay, redaction: .standard, onShow: { _ in }, links: NetworkReplayLinks(of: replay, in: [replay]))

            let actual = try sut.inspect().find(DebugDrawerKeyValueRow.self, where: { try $0.actualView().label == "Replay of" }).actualView().value

            #expect(actual == "A request no longer in the log")
            #expect(throws: (any Error).self) { try sut.inspect().find(button: "Show") }
        }

        @Test("A resend in progress shows Resending and can't be sent again; a failed one says why")
        func statuses() throws {
            let entry = NetworkEntry(
                timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000), method: "GET", url: "https://example.com/",
                host: "example.com", path: "/", requestHeaders: [:], requestBody: nil, statusCode: 200, isComplete: true
            )
            let sending = NetworkRequestDetail(entry: entry, redaction: .standard, onResend: { _ in }, replayStatus: .sending)
            let failed = NetworkRequestDetail(
                entry: entry, redaction: .standard, onResend: { _ in }, replayStatus: .failed("The Internet connection appears to be offline.")
            )

            let progress = try sending.inspect().find(text: "Resending…").string()
            let isDisabled = try sending.inspect().find(button: "Resend").isDisabled()
            let title = try failed.inspect().find(text: "Resend failed").string()
            let message = try failed.inspect().find(text: "The Internet connection appears to be offline.").string()

            #expect(progress == "Resending…")
            #expect(isDisabled)
            #expect(title == "Resend failed")
            #expect(message == "The Internet connection appears to be offline.")
        }

        // MARK: Edit and Resend

        @Test("Edit and Resend starts from the request; an edited URL and header are what Send hands over")
        func editorSendsEdits() async throws {
            let entry = NetworkEntry(
                timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000), method: "GET", url: "https://api.example.com/v1/users/1",
                host: "api.example.com", path: "/v1/users/1", requestHeaders: ["X-Client": "app"], requestBody: nil, statusCode: 200, isComplete: true
            )
            var sent: [URLRequest] = []
            let sut = NetworkReplayEditor(draft: NetworkReplayDraft(entry), cancel: {}, send: { sent.append($0) })
            var prefilledURL = ""

            try await ViewHosting.host(sut) {
                try await sut.inspection.inspect { view in
                    let url = try view.find(ViewType.TextField.self, where: { try $0.accessibilityLabel().string() == "URL" })
                    prefilledURL = try url.input()
                    try url.setInput("https://staging.example.com/v1/users/2")
                    try view.find(ViewType.TextField.self, where: { try $0.accessibilityLabel().string() == "Header value" }).setInput("drawer")
                }
                try await sut.inspection.inspect { view in
                    try view.find(button: "Send").tap()
                }
            }

            let actual = try #require(sent.first)
            #expect(prefilledURL == "https://api.example.com/v1/users/1")
            #expect(sent.count == 1)
            #expect(actual.url?.absoluteString == "https://staging.example.com/v1/users/2")
            #expect(actual.value(forHTTPHeaderField: "X-Client") == "drawer")
            #expect(actual.httpMethod == "GET")
        }

        @Test("An invalid URL says why below its field, and Send stays unavailable until it is fixed")
        func editorInvalidURL() async throws {
            let entry = NetworkEntry(
                timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000), method: "GET", url: "https://example.com/",
                host: "example.com", path: "/", requestHeaders: [:], requestBody: nil, statusCode: 200, isComplete: true
            )
            var sent: [URLRequest] = []
            let sut = NetworkReplayEditor(draft: NetworkReplayDraft(entry), cancel: {}, send: { sent.append($0) })
            var problem = false
            var disabled = false
            var disabledAfter = true

            try await ViewHosting.host(sut) {
                try await sut.inspection.inspect { view in
                    try view.find(ViewType.TextField.self, where: { try $0.accessibilityLabel().string() == "URL" }).setInput("example.com/no-scheme")
                }
                try await sut.inspection.inspect { view in
                    problem = (try? view.find(text: "Enter an http or https URL with a host.")) != nil
                    disabled = try view.find(button: "Send").isDisabled()
                    try view.find(ViewType.TextField.self, where: { try $0.accessibilityLabel().string() == "URL" })
                        .setInput("https://example.com/fixed")
                }
                try await sut.inspection.inspect { view in
                    disabledAfter = try view.find(button: "Send").isDisabled()
                }
            }

            #expect(problem)
            #expect(disabled)
            #expect(!disabledAfter)
            #expect(sent.isEmpty)
        }

        @Test("A GET with a body says it can't carry one, and Send is unavailable")
        func editorGetWithBody() async throws {
            let entry = NetworkEntry(
                timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000), method: "GET", url: "https://example.com/",
                host: "example.com", path: "/", requestHeaders: [:], requestBody: nil, statusCode: 200, isComplete: true
            )
            let sut = NetworkReplayEditor(draft: NetworkReplayDraft(entry), cancel: {}, send: { _ in })
            var problem = false
            var disabled = false

            try await ViewHosting.host(sut) {
                try await sut.inspection.inspect { view in
                    try view.find(ViewType.TextEditor.self).setInput("q=1")
                }
                try await sut.inspection.inspect { view in
                    problem = (try? view.find(text: "A GET can't carry a body. Remove it, or choose another method.")) != nil
                    disabled = try view.find(button: "Send").isDisabled()
                }
            }

            #expect(problem)
            #expect(disabled)
        }

        @Test("Sending a POST from the editor asks first; Cancel sends nothing, and Send in the question sends it")
        func editorPostAsksFirst() async throws {
            let entry = NetworkEntry(
                timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000), method: "POST", url: "https://api.example.com/v1/orders",
                host: "api.example.com", path: "/v1/orders", requestHeaders: [:], requestBody: Data("{}".utf8), statusCode: 201, isComplete: true
            )
            var sent: [URLRequest] = []
            let sut = NetworkReplayEditor(draft: NetworkReplayDraft(entry), cancel: {}, send: { sent.append($0) })
            var sentAfterCancel: [URLRequest] = []
            var questionAfterCancel = true

            try await ViewHosting.host(sut) {
                try await sut.inspection.inspect { view in
                    try view.find(button: "Send").tap()
                }
                try await sut.inspection.inspect { view in
                    try view.find(NetworkResendConfirmation.self).find(button: "Cancel").tap()
                }
                try await sut.inspection.inspect { view in
                    sentAfterCancel = sent
                    questionAfterCancel = (try? view.find(NetworkResendConfirmation.self)) != nil
                    try view.find(button: "Send").tap()
                }
                try await sut.inspection.inspect { view in
                    try view.find(NetworkResendConfirmation.self).find(button: "Send").tap()
                }
            }

            #expect(sentAfterCancel.isEmpty)
            #expect(!questionAfterCancel)
            #expect(sent.map(\.httpMethod) == ["POST"])
            #expect(sent.first?.httpBody == Data("{}".utf8))
        }

        @Test("A body that isn't text is described, kept, and can be removed")
        func editorBinaryBody() async throws {
            let entry = NetworkEntry(
                timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000), method: "PUT", url: "https://example.com/upload",
                host: "example.com", path: "/upload", requestHeaders: [:], requestBody: Data([0xFF, 0xFE, 0x00]), isComplete: true
            )
            let sut = NetworkReplayEditor(draft: NetworkReplayDraft(entry), cancel: {}, send: { _ in })
            var note = ""
            var editorAfter = false

            try await ViewHosting.host(sut) {
                try await sut.inspection.inspect { view in
                    note = try view.find(textWhere: { text, _ in text.hasSuffix("bytes that aren't text, sent as captured.") }).string()
                    try view.find(button: "Remove Body").tap()
                }
                try await sut.inspection.inspect { view in
                    editorAfter = (try? view.find(ViewType.TextEditor.self)) != nil
                }
            }

            #expect(note == "3 bytes that aren't text, sent as captured.")
            #expect(editorAfter)
        }
    }
#endif
