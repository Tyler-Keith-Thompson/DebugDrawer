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
    struct NetworkSessionViewTests {
        @Test("With an earlier session kept, the log offers the current session's requests and the previous ones as separate segments")
        func separateSegments() throws {
            final class Selection {
                var source = NetworkLogSource.captured
            }
            let selection = Selection()
            let sut = NetworkLogSourcePicker(
                source: Binding(get: { selection.source }, set: { selection.source = $0 }),
                fileName: "",
                count: 0,
                sources: [.captured, .previous]
            )

            let view = try sut.inspect()
            try view.find(ViewType.Picker.self).select(value: NetworkLogSource.previous)

            #expect(throws: Never.self) { try view.find(text: "Captured") }
            #expect(throws: Never.self) { try view.find(text: "Previous") }
            #expect((try? view.find(text: "Imported")) == nil)
            #expect(selection.source == .previous)
        }

        @Test("Under Previous, the menu lists each earlier session by start and size, and the shown one's requests are read-only")
        func previousSession() throws {
            let started = Date(timeIntervalSince1970: 1_800_000_000)
            let entries = [
                NetworkEntry(
                    timestamp: started.addingTimeInterval(1), method: "GET", url: "https://api.example.com/v1/orders", host: "api.example.com",
                    path: "/v1/orders", requestHeaders: [:], requestBody: nil, statusCode: 200, isComplete: true
                ),
                NetworkEntry(
                    timestamp: started.addingTimeInterval(2), method: "GET", url: "https://api.example.com/v1/cart", host: "api.example.com",
                    path: "/v1/cart", requestHeaders: [:], requestBody: nil, statusCode: 500, isComplete: true
                )
            ]
            let encoder = JSONEncoder()
            let header = NetworkSessionHeader(started: "2027-01-15T08:00:00.000Z", app: "Shop", appVersion: "2.1 (40)")
            let lines = try [encoder.encode(header)] + entries.map { try encoder.encode(HTTPArchive.Entry($0, original: nil, redaction: .standard)) }
            let data = Data(lines.joined(separator: Data("\n".utf8)))
            let newest = try #require(NetworkSessionSummary(NetworkSessionFile(
                name: NetworkSessionSummary.name(started: started, id: UUID()), byteCount: 48_000
            )))
            let older = try #require(NetworkSessionSummary(NetworkSessionFile(
                name: NetworkSessionSummary.name(started: started.addingTimeInterval(-3_600), id: UUID()), byteCount: 2_000
            )))
            let sut = NetworkPreviousSessionPicker(
                sessions: [newest, older], shown: NetworkSessionLog(summary: newest, data: data), select: { _ in }, deleteAll: {}
            )

            let newestTitle = newest.title(locale: Locale(identifier: "en_US"), timeZone: .gmt)
            let olderTitle = older.title(locale: Locale(identifier: "en_US"), timeZone: .gmt)

            let view = try sut.environment(\.locale, Locale(identifier: "en_US")).environment(\.timeZone, .gmt).inspect()

            #expect(throws: Never.self) { try view.find(text: newestTitle) }
            #expect(throws: Never.self) { try view.find(text: olderTitle) }
            #expect(throws: Never.self) { try view.find(text: "Shop 2.1 (40)") }
            #expect(throws: Never.self) { try view.find(text: "2, read-only") }
            #expect(newestTitle.hasPrefix("Jan 15 at 8:00:00"))
            #expect(newestTitle.hasSuffix("48 kB"))
            #expect(olderTitle.hasPrefix("Jan 15 at 7:00:00"))
        }

        @Test("Picking another session in the menu asks for it, and Delete All Sessions asks once")
        func pickAndDeleteAll() throws {
            let started = Date(timeIntervalSince1970: 1_800_000_000)
            let newest = try #require(NetworkSessionSummary(NetworkSessionFile(
                name: NetworkSessionSummary.name(started: started, id: UUID()), byteCount: 1_000
            )))
            let older = try #require(NetworkSessionSummary(NetworkSessionFile(
                name: NetworkSessionSummary.name(started: started.addingTimeInterval(-60), id: UUID()), byteCount: 1_000
            )))
            var picked: [String] = []
            var deletes = 0
            let sut = NetworkPreviousSessionPicker(sessions: [newest, older], shown: nil, select: { picked.append($0) }, deleteAll: { deletes += 1 })

            let view = try sut.inspect()
            try view.find(ViewType.Picker.self).select(value: older.id)
            try view.find(button: "Delete All Sessions").tap()

            #expect(picked == [older.id])
            #expect(deletes == 1)
        }

        @Test("Under Previous, the toolbar's trailing button deletes the session shown, and says so")
        func toolbarDeletes() throws {
            var deletes = 0
            let sut = NetworkToolbar(filterStatus: .constant(.all), clear: { deletes += 1 }, importArchive: {}, source: .previous)
            let expected = "Delete this session"

            let button = try sut.inspect().find(button: "Delete")
            let actual = try button.accessibilityLabel().string()
            try button.tap()

            #expect(actual == expected)
            #expect(deletes == 1)
        }

        @Test("A previous session's request offers Copy cURL and Mock This under More, but neither Resend nor Edit and Resend")
        func previousEntryReadOnly() throws {
            let entry = NetworkEntry(
                timestamp: Date(timeIntervalSince1970: 0), method: "GET", url: "https://shop.example.com/api/cart",
                host: "shop.example.com", path: "/api/cart", requestHeaders: [:], requestBody: nil, statusCode: 200, isComplete: true
            )
            let isReadOnly = NetworkLogSource.previous.isReadOnly
            let sut = NetworkRequestDetail(
                entry: entry, redaction: .standard, onMock: { _ in },
                onResend: isReadOnly ? nil : { _ in }, onEditAndResend: isReadOnly ? nil : { _ in }
            )

            let view = try sut.inspect()

            #expect(isReadOnly)
            #expect(!NetworkLogSource.captured.isReadOnly)
            #expect(throws: Never.self) { try view.find(text: "Copy cURL") }
            #expect(throws: Never.self) { try view.find(button: "Mock This") }
            #expect((try? view.find(button: "Resend")) == nil)
        }
    }
#endif
