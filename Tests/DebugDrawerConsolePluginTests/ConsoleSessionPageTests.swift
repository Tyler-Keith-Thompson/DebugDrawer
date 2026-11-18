#if DEBUG
    @testable import DebugDrawerConsolePlugin
    import Foundation
    import Testing

    @Suite(.timeLimit(.minutes(1)))
    struct ConsoleSessionPageTests {
        @Test("A page lists the newest lines the filter passes, up to its limit, and counts the earlier ones it leaves out")
        func newestMatchingLines() throws {
            let started = Date(timeIntervalSince1970: 1_800_000_000)
            let encoder = JSONEncoder()
            let levels: [LogLine.Level] = [.info, .debug, .info, .error, .debug, .info]
            let lines = levels.enumerated().map { index, level in
                LogLine(timestamp: started.addingTimeInterval(Double(index)), text: "line \(index)", source: .oslog, level: level)
            }
            let data = try Data(lines.map { try encoder.encode(ConsoleSessionLine($0)) }.joined(separator: Data("\n".utf8)))
            let summary = try #require(ConsoleSessionSummary(ConsoleSessionFile(
                name: ConsoleSessionSummary.name(started: started, id: UUID()), byteCount: data.count
            )))
            let log = ConsoleSessionLog(summary: summary, data: data)
            var filter = ConsoleFilter()
            filter.level = .info
            let expected = ["line 3", "line 5"]

            let sut = ConsoleSessionPage(log: log, filter: filter, lineLimit: 2)

            #expect(sut.lines.map(\.text) == expected)
            #expect(sut.earlierCount == 2)
        }

        @Test("Show Earlier adds up to a page of older matching lines, and stops at the session's first")
        func showingEarlier() throws {
            let started = Date(timeIntervalSince1970: 1_800_000_000)
            let encoder = JSONEncoder()
            let count = ConsoleSessionPage.lineCount + 500
            let lines = (0 ..< count).map { index in
                LogLine(timestamp: started.addingTimeInterval(Double(index)), text: "line \(index)", source: .stdout, level: .info)
            }
            let data = try Data(lines.map { try encoder.encode(ConsoleSessionLine($0)) }.joined(separator: Data("\n".utf8)))
            let summary = try #require(ConsoleSessionSummary(ConsoleSessionFile(
                name: ConsoleSessionSummary.name(started: started, id: UUID()), byteCount: data.count
            )))
            let sut = ConsoleSessionPage(log: ConsoleSessionLog(summary: summary, data: data), filter: ConsoleFilter())
            let expectedFirst = "line 500"

            let earlier = sut.showingEarlier()
            let earliest = earlier.showingEarlier()

            #expect(sut.lines.count == ConsoleSessionPage.lineCount)
            #expect(sut.lines.first?.text == expectedFirst)
            #expect(sut.earlierCount == 500)
            #expect(earlier.lines.count == count)
            #expect(earlier.lines.first?.text == "line 0")
            #expect(earlier.earlierCount == 0)
            #expect(earliest.lines.count == count)
        }

        @Test("A page whose limit is exactly the matching lines leaves none out; one short leaves out the oldest")
        func limitBoundaries() throws {
            let started = Date(timeIntervalSince1970: 1_800_000_000)
            let encoder = JSONEncoder()
            let lines = (0 ..< 3).map { index in
                LogLine(timestamp: started.addingTimeInterval(Double(index)), text: "line \(index)", source: .stdout, level: .info)
            }
            let data = try Data(lines.map { try encoder.encode(ConsoleSessionLine($0)) }.joined(separator: Data("\n".utf8)))
            let summary = try #require(ConsoleSessionSummary(ConsoleSessionFile(
                name: ConsoleSessionSummary.name(started: started, id: UUID()), byteCount: data.count
            )))
            let log = ConsoleSessionLog(summary: summary, data: data)

            let exact = ConsoleSessionPage(log: log, filter: ConsoleFilter(), lineLimit: 3)
            let short = ConsoleSessionPage(log: log, filter: ConsoleFilter(), lineLimit: 2)
            let one = ConsoleSessionPage(log: log, filter: ConsoleFilter(), lineLimit: 1)

            #expect(exact.lines.map(\.text) == ["line 0", "line 1", "line 2"])
            #expect(exact.earlierCount == 0)
            #expect(short.lines.map(\.text) == ["line 1", "line 2"])
            #expect(short.earlierCount == 1)
            #expect(one.lines.map(\.text) == ["line 2"])
            #expect(one.earlierCount == 2)
        }

        @Test("An empty session's page lists nothing, leaves nothing out, and offers no mutes")
        func emptySession() throws {
            let summary = try #require(ConsoleSessionSummary(ConsoleSessionFile(
                name: ConsoleSessionSummary.name(started: Date(timeIntervalSince1970: 1_800_000_000), id: UUID()), byteCount: 0
            )))

            let sut = ConsoleSessionPage(log: ConsoleSessionLog(summary: summary, data: Data()), filter: ConsoleFilter())

            #expect(sut.lines.isEmpty)
            #expect(sut.earlierCount == 0)
            #expect(sut.mutedCount == 0)
            #expect(sut.muteChoices.isEmpty)
        }

        @Test("A page counts what the mutes hide and offers the mutes of the whole session, not only of the lines it lists")
        func mutesOverTheWholeSession() throws {
            let started = Date(timeIntervalSince1970: 1_800_000_000)
            let encoder = JSONEncoder()
            let lines = [
                LogLine(timestamp: started, text: "Feed", source: .oslog, level: .info, subsystem: "com.example.feed", category: "net"),
                LogLine(timestamp: started.addingTimeInterval(1), text: "Cart", source: .oslog, level: .info, subsystem: "com.example.cart"),
                LogLine(timestamp: started.addingTimeInterval(2), text: "Feed again", source: .oslog, level: .info, subsystem: "com.example.feed"),
                LogLine(timestamp: started.addingTimeInterval(3), text: "printed", source: .stdout, level: .info)
            ]
            let data = try Data(lines.map { try encoder.encode(ConsoleSessionLine($0)) }.joined(separator: Data("\n".utf8)))
            let summary = try #require(ConsoleSessionSummary(ConsoleSessionFile(
                name: ConsoleSessionSummary.name(started: started, id: UUID()), byteCount: data.count
            )))
            var filter = ConsoleFilter()
            filter.mutes = [.subsystem("com.example.feed")]
            let expectedChoices: [ConsoleMute] = [.subsystem("com.example.cart")]

            let sut = ConsoleSessionPage(log: ConsoleSessionLog(summary: summary, data: data), filter: filter, lineLimit: 1)

            #expect(sut.lines.map(\.text) == ["printed"])
            #expect(sut.earlierCount == 1)
            #expect(sut.mutedCount == 2)
            #expect(sut.muteChoices == expectedChoices)
        }

        @Test("Filtering a page again keeps how many lines it lists")
        func filteredKeepsTheLimit() throws {
            let started = Date(timeIntervalSince1970: 1_800_000_000)
            let encoder = JSONEncoder()
            let lines = (0 ..< 6).map { index in
                LogLine(
                    timestamp: started.addingTimeInterval(Double(index)), text: "line \(index)", source: .oslog,
                    level: index.isMultiple(of: 2) ? .error : .info
                )
            }
            let data = try Data(lines.map { try encoder.encode(ConsoleSessionLine($0)) }.joined(separator: Data("\n".utf8)))
            let summary = try #require(ConsoleSessionSummary(ConsoleSessionFile(
                name: ConsoleSessionSummary.name(started: started, id: UUID()), byteCount: data.count
            )))
            var errors = ConsoleFilter()
            errors.level = .error
            let sut = ConsoleSessionPage(log: ConsoleSessionLog(summary: summary, data: data), filter: ConsoleFilter(), lineLimit: 2)

            let actual = sut.filtered(by: errors)

            #expect(actual.lineLimit == 2)
            #expect(actual.filter == errors)
            #expect(actual.lines.map(\.text) == ["line 2", "line 4"])
            #expect(actual.earlierCount == 1)
        }

        @MainActor
        @Test("The store shows the page it is handed as it is, so opening a session draws a page rather than the session")
        func storeShowsThePreparedPage() async throws {
            let started = Date(timeIntervalSince1970: 1_800_000_000)
            let encoder = JSONEncoder()
            let count = ConsoleSessionPage.lineCount * 3
            let lines = (0 ..< count).map { index in
                LogLine(timestamp: started.addingTimeInterval(Double(index)), text: "line \(index)", source: .stdout, level: .info)
            }
            let data = try Data(lines.map { try encoder.encode(ConsoleSessionLine($0)) }.joined(separator: Data("\n".utf8)))
            let summary = try #require(ConsoleSessionSummary(ConsoleSessionFile(
                name: ConsoleSessionSummary.name(started: started, id: UUID()), byteCount: data.count
            )))
            let sut = ConsoleLogStore(muteStorage: FakeConsoleMuteStorage())
            let page = await ConsoleSessionPage.prepared(log: ConsoleSessionLog(summary: summary, data: data), filter: sut.filter)
            let expected = page.lines.map(\.id)

            sut.showPrevious(page)
            let shown = sut.shownLines.map(\.id)
            sut.showEarlierPreviousLines()

            #expect(sut.source == .previous)
            #expect(shown == expected)
            #expect(shown.count == ConsoleSessionPage.lineCount)
            #expect(sut.shownLines.count == ConsoleSessionPage.lineCount * 2)
            #expect(sut.previousPage?.earlierCount == ConsoleSessionPage.lineCount)
        }

        @MainActor
        @Test("A page worked out before the filter changed is filtered again when the store is handed it")
        func storeRefiltersAStalePage() async throws {
            let started = Date(timeIntervalSince1970: 1_800_000_000)
            let encoder = JSONEncoder()
            let lines = [
                LogLine(timestamp: started, text: "Loaded", source: .oslog, level: .info),
                LogLine(timestamp: started.addingTimeInterval(1), text: "Failed", source: .oslog, level: .error)
            ]
            let data = try Data(lines.map { try encoder.encode(ConsoleSessionLine($0)) }.joined(separator: Data("\n".utf8)))
            let summary = try #require(ConsoleSessionSummary(ConsoleSessionFile(
                name: ConsoleSessionSummary.name(started: started, id: UUID()), byteCount: data.count
            )))
            let sut = ConsoleLogStore(muteStorage: FakeConsoleMuteStorage())
            let page = await ConsoleSessionPage.prepared(log: ConsoleSessionLog(summary: summary, data: data), filter: sut.filter)
            sut.filterLevel = .error

            sut.showPrevious(page)

            #expect(sut.shownLines.map(\.text) == ["Failed"])
            #expect(sut.previousPage?.filter == sut.filter)
        }
    }
#endif
