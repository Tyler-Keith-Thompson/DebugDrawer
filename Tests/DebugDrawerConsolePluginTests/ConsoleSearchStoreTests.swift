#if DEBUG
    @testable import DebugDrawerConsolePlugin
    import Foundation
    import Testing

    // Lines reach the store through an earlier session shown under Previous, which shows them at
    // once; captured lines arrive through the store's batching, on a timer the tests can't steer.
    @MainActor
    @Suite
    struct ConsoleSearchStoreTests {
        @Test("A regular-expression search lists only the lines that fit the pattern")
        func regularExpression() throws {
            let header = #"{"debugDrawerConsoleSession":1,"started":"2027-01-15T08:00:00.000Z","app":"Shop","appVersion":""}"#
            let rows = [
                #"{"level":"info","source":"oslog","text":"GET /feed 200","time":"2027-01-15T08:00:01.000Z"}"#,
                #"{"level":"error","source":"oslog","text":"GET /feed 503","time":"2027-01-15T08:00:02.000Z"}"#,
                #"{"level":"info","source":"oslog","text":"feed 503 retried","time":"2027-01-15T08:00:03.000Z"}"#
            ]
            let data = Data(([header] + rows).joined(separator: "\n").utf8)
            let summary = try #require(ConsoleSessionSummary(ConsoleSessionFile(
                name: ConsoleSessionSummary.name(started: Date(timeIntervalSince1970: 1_800_000_000), id: UUID()), byteCount: data.count
            )))
            let sut = ConsoleLogStore(muteStorage: FakeConsoleMuteStorage())
            sut.showPrevious(ConsoleSessionLog(summary: summary, data: data))
            let expected = ["GET /feed 503"]

            sut.searchIsRegularExpression = true
            sut.searchText = #"^GET .* 5\d\d$"#

            #expect(sut.shownLines.map(\.text) == expected)
            #expect(sut.searchIssue == nil)
        }

        @Test("An invalid pattern names the problem and leaves the list as the last valid search had it")
        func invalidPatternKeepsTheList() throws {
            let header = #"{"debugDrawerConsoleSession":1,"started":"2027-01-15T08:00:00.000Z","app":"Shop","appVersion":""}"#
            let rows = [
                #"{"level":"info","source":"oslog","text":"feed loaded","time":"2027-01-15T08:00:01.000Z"}"#,
                #"{"level":"info","source":"oslog","text":"cart shown","time":"2027-01-15T08:00:02.000Z"}"#
            ]
            let data = Data(([header] + rows).joined(separator: "\n").utf8)
            let summary = try #require(ConsoleSessionSummary(ConsoleSessionFile(
                name: ConsoleSessionSummary.name(started: Date(timeIntervalSince1970: 1_800_000_000), id: UUID()), byteCount: data.count
            )))
            let sut = ConsoleLogStore(muteStorage: FakeConsoleMuteStorage())
            sut.showPrevious(ConsoleSessionLog(summary: summary, data: data))
            sut.searchIsRegularExpression = true
            sut.searchText = "fe+d"
            let expected = ["feed loaded"]

            sut.searchText = "fe+d("
            let actual = sut.shownLines.map(\.text)

            #expect(actual == expected)
            #expect(sut.searchIssue == ConsoleSearch.InvalidPattern())
            #expect(sut.searchIssue?.message == "Not a valid regular expression. The list keeps the last valid search.")
        }

        @Test("Fixing the pattern, or turning the toggle off, clears the problem")
        func fixingClearsTheIssue() {
            let sut = ConsoleLogStore(muteStorage: FakeConsoleMuteStorage())
            sut.searchIsRegularExpression = true
            sut.searchText = "["

            let invalid = sut.searchIssue
            sut.searchIsRegularExpression = false
            let asText = sut.searchIssue
            let search = sut.filter.search

            #expect(invalid != nil)
            #expect(asText == nil)
            #expect(search == .text("["))
        }

        @Test("A time range from a line holds for its own source and goes back to All when the source changes")
        func sinceResetsOnSourceChange() {
            let sut = ConsoleLogStore(muteStorage: FakeConsoleMuteStorage())
            sut.timeRange = .since(Date(timeIntervalSince1970: 1_800_000_000))

            sut.source = .previous

            #expect(sut.timeRange == .all)
        }

        @Test("A preset time range holds across sources")
        func presetHoldsOnSourceChange() {
            let sut = ConsoleLogStore(muteStorage: FakeConsoleMuteStorage())
            sut.timeRange = .last(minutes: 5)

            sut.source = .previous

            #expect(sut.timeRange == .last(minutes: 5))
        }
    }
#endif
