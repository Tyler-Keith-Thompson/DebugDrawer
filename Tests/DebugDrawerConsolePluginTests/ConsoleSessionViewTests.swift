// ViewInspector is linked on Apple platforms only, and the views are tested on the Mac.
#if os(macOS)
    @testable import DebugDrawer
    @testable import DebugDrawerConsolePlugin
    import Foundation
    import SwiftUI
    import Testing
    import ViewInspector

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct ConsoleSessionViewTests {
        @Test("With an earlier session kept, the console offers the current session's lines and the previous ones as separate segments")
        func separateSegments() throws {
            final class Selection {
                var source = ConsoleLogSource.captured
            }
            let selection = Selection()
            let sut = ConsoleLogSourcePicker(source: Binding(get: { selection.source }, set: { selection.source = $0 }))

            let view = try sut.inspect()
            try view.find(ViewType.Picker.self).select(value: ConsoleLogSource.previous)

            #expect(throws: Never.self) { try view.find(text: "Captured") }
            #expect(throws: Never.self) { try view.find(text: "Previous") }
            #expect(selection.source == .previous)
        }

        @Test("Under Previous, the menu lists each earlier session by start and size, and the shown one's lines are counted read-only")
        func previousSession() throws {
            let started = Date(timeIntervalSince1970: 1_800_000_000)
            let encoder = JSONEncoder()
            let header = ConsoleSessionHeader(started: "2027-01-15T08:00:00.000Z", app: "Shop", appVersion: "2.1 (40)")
            let lines = [
                LogLine(timestamp: started.addingTimeInterval(1), text: "App launched", source: .oslog, level: .info),
                LogLine(timestamp: started.addingTimeInterval(2), text: "Decoding failed", source: .stderr, level: .error)
            ]
            let rows = try [encoder.encode(header)] + lines.map { try encoder.encode(ConsoleSessionLine($0)) } + [Data(#"{"lev"#.utf8)]
            let data = Data(rows.joined(separator: Data("\n".utf8)))
            let newest = try #require(ConsoleSessionSummary(ConsoleSessionFile(
                name: ConsoleSessionSummary.name(started: started, id: UUID()), byteCount: 48_000
            )))
            let older = try #require(ConsoleSessionSummary(ConsoleSessionFile(
                name: ConsoleSessionSummary.name(started: started.addingTimeInterval(-3_600), id: UUID()), byteCount: 2_000
            )))
            let sut = ConsolePreviousSessionPicker(
                sessions: [newest, older], shown: ConsoleSessionLog(summary: newest, data: data), select: { _ in }, deleteAll: {}
            )

            let newestTitle = newest.title(locale: Locale(identifier: "en_US"), timeZone: .gmt)
            let olderTitle = older.title(locale: Locale(identifier: "en_US"), timeZone: .gmt)

            let view = try sut.environment(\.locale, Locale(identifier: "en_US")).environment(\.timeZone, .gmt).inspect()

            #expect(throws: Never.self) { try view.find(text: newestTitle) }
            #expect(throws: Never.self) { try view.find(text: olderTitle) }
            #expect(throws: Never.self) { try view.find(text: "Shop 2.1 (40)") }
            #expect(throws: Never.self) { try view.find(text: "2, read-only") }
            #expect(throws: Never.self) { try view.find(text: "1 line") }
            #expect(newestTitle.hasPrefix("Jan 15 at 8:00:00"))
            #expect(newestTitle.hasSuffix("48 kB"))
            #expect(olderTitle.hasPrefix("Jan 15 at 7:00:00"))
        }

        @Test("Picking another session in the menu asks for it, and Delete All Sessions asks once")
        func pickAndDeleteAll() throws {
            let started = Date(timeIntervalSince1970: 1_800_000_000)
            let newest = try #require(ConsoleSessionSummary(ConsoleSessionFile(
                name: ConsoleSessionSummary.name(started: started, id: UUID()), byteCount: 1_000
            )))
            let older = try #require(ConsoleSessionSummary(ConsoleSessionFile(
                name: ConsoleSessionSummary.name(started: started.addingTimeInterval(-60), id: UUID()), byteCount: 1_000
            )))
            var picked: [String] = []
            var deletes = 0
            let sut = ConsolePreviousSessionPicker(sessions: [newest, older], shown: nil, select: { picked.append($0) }, deleteAll: { deletes += 1 })

            let view = try sut.inspect()
            try view.find(ViewType.Picker.self).select(value: older.id)
            try view.find(button: "Delete All Sessions").tap()

            #expect(picked == [older.id])
            #expect(deletes == 1)
        }

        @Test("Under Previous, the toolbar's trailing button deletes the session shown, and says so")
        func toolbarDeletes() throws {
            var deletes = 0
            let sut = ConsoleToolbarView(
                isFollowing: .constant(true), filterLevel: .constant(.debug),
                clear: { deletes += 1 }, source: .previous
            )
            let expected = "Delete this session"

            let button = try sut.inspect().find(button: "Delete")
            let actual = try button.accessibilityLabel().string()
            try button.tap()

            #expect(actual == expected)
            #expect(deletes == 1)
        }

        @Test("Under Captured, the toolbar's trailing button clears the console")
        func toolbarClears() throws {
            var clears = 0
            let sut = ConsoleToolbarView(
                isFollowing: .constant(true), filterLevel: .constant(.debug),
                clear: { clears += 1 }
            )
            let expected = "Clear the console"

            let button = try sut.inspect().find(button: "Clear")
            let actual = try button.accessibilityLabel().string()
            try button.tap()

            #expect(actual == expected)
            #expect(clears == 1)
            #expect((try? sut.inspect().find(button: "Delete")) == nil)
        }
    }
#endif
