#if DEBUG
    @testable import DebugDrawerConsolePlugin
    import Foundation
    import Testing

    @Suite
    struct ConsoleFilterTests {
        @Test("The default filter passes every line, in order")
        func passesEverything() {
            let start = Date(timeIntervalSince1970: 1_800_000_000)
            let lines = [
                LogLine(timestamp: start, text: "App launched", source: .stdout, level: .debug),
                LogLine(timestamp: start.addingTimeInterval(1), text: "Feed loaded", source: .oslog, level: .info, subsystem: "com.example.feed")
            ]
            let sut = ConsoleFilter()
            let expected = ["App launched", "Feed loaded"]

            let actual = sut.apply(to: lines).map(\.text)

            #expect(actual == expected)
        }

        @Test("No lines pass as no lines, whatever the filter")
        func noLines() throws {
            var sut = ConsoleFilter()
            sut.search = try ConsoleSearch("feed", isRegularExpression: true)
            sut.timeRange = .last(minutes: 1)
            sut.mutes = [.subsystem("com.example.feed")]

            let actual = sut.apply(to: [])

            #expect(actual.isEmpty)
            #expect(sut.mutedCount(in: []) == 0)
        }

        @Test("The level hides the lines below it")
        func level() {
            let start = Date(timeIntervalSince1970: 1_800_000_000)
            let lines = [
                LogLine(timestamp: start, text: "debug", source: .oslog, level: .debug),
                LogLine(timestamp: start, text: "info", source: .oslog, level: .info),
                LogLine(timestamp: start, text: "error", source: .stderr, level: .error),
                LogLine(timestamp: start, text: "fault", source: .oslog, level: .fault)
            ]
            var sut = ConsoleFilter()
            sut.level = .error
            let expected = ["error", "fault"]

            let actual = sut.apply(to: lines).map(\.text)

            #expect(actual == expected)
        }

        @Test("A text search matches the text, subsystem or category, ignoring case")
        func textSearch() throws {
            let start = Date(timeIntervalSince1970: 1_800_000_000)
            let lines = [
                LogLine(timestamp: start, text: "Feed loaded", source: .oslog, level: .info),
                LogLine(timestamp: start, text: "Cart saved", source: .oslog, level: .info, subsystem: "com.example.FEED"),
                LogLine(timestamp: start, text: "Token refreshed", source: .oslog, level: .info, subsystem: "com.example.auth", category: "feeder"),
                LogLine(timestamp: start, text: "Checkout", source: .oslog, level: .info, subsystem: "com.example.cart", category: "ui")
            ]
            var sut = ConsoleFilter()
            sut.search = try ConsoleSearch("feed", isRegularExpression: false)
            let expected = ["Feed loaded", "Cart saved", "Token refreshed"]

            let actual = sut.apply(to: lines).map(\.text)

            #expect(actual == expected)
        }

        @Test("A text search reads regular-expression characters as themselves")
        func textSearchIsLiteral() throws {
            let start = Date(timeIntervalSince1970: 1_800_000_000)
            let lines = [
                LogLine(timestamp: start, text: "a.*b", source: .stdout, level: .info),
                LogLine(timestamp: start, text: "axxb", source: .stdout, level: .info)
            ]
            var sut = ConsoleFilter()
            sut.search = try ConsoleSearch("a.*b", isRegularExpression: false)
            let expected = ["a.*b"]

            let actual = sut.apply(to: lines).map(\.text)

            #expect(actual == expected)
        }

        @Test("A regular-expression search passes only the lines the pattern finds a match in")
        func regularExpressionSearch() throws {
            let start = Date(timeIntervalSince1970: 1_800_000_000)
            let lines = [
                LogLine(timestamp: start, text: "GET /feed 200", source: .oslog, level: .info),
                LogLine(timestamp: start, text: "GET /feed 503", source: .oslog, level: .error),
                LogLine(timestamp: start, text: "POST /cart 500", source: .oslog, level: .error),
                LogLine(timestamp: start, text: "status 5xx", source: .oslog, level: .info)
            ]
            var sut = ConsoleFilter()
            sut.search = try ConsoleSearch(#"^(get|post) /\w+ 5\d\d$"#, isRegularExpression: true)
            let expected = ["GET /feed 503", "POST /cart 500"]

            let actual = sut.apply(to: lines).map(\.text)

            #expect(actual == expected)
        }

        @Test("A pattern matches a line's subsystem and category too")
        func regularExpressionMatchesOrigin() throws {
            let start = Date(timeIntervalSince1970: 1_800_000_000)
            let lines = [
                LogLine(timestamp: start, text: "one", source: .oslog, level: .info, subsystem: "com.example.feed", category: "net"),
                LogLine(timestamp: start, text: "two", source: .oslog, level: .info, subsystem: "com.example.cart", category: "ui")
            ]
            var sut = ConsoleFilter()
            sut.search = try ConsoleSearch(#"^net$"#, isRegularExpression: true)
            let expected = ["one"]

            let actual = sut.apply(to: lines).map(\.text)

            #expect(actual == expected)
        }

        @Test("A pattern NSRegularExpression can't read throws InvalidPattern")
        func invalidPattern() {
            let pattern = "(feed"

            #expect(throws: ConsoleSearch.InvalidPattern()) {
                try ConsoleSearch(pattern, isRegularExpression: true)
            }
        }

        @Test("The same text that isn't a pattern is a valid text search")
        func invalidPatternAsText() throws {
            let expected = ConsoleSearch.text("(feed")

            let actual = try ConsoleSearch("(feed", isRegularExpression: false)

            #expect(actual == expected)
        }

        @Test("An empty search matches every line, as text or as a pattern")
        func emptySearch() throws {
            let text = try ConsoleSearch("", isRegularExpression: false)
            let pattern = try ConsoleSearch("", isRegularExpression: true)

            #expect(text == .all)
            #expect(pattern == .all)
        }

        @Test("Last 5 Minutes passes the lines logged in the five minutes up to the newest, the boundary included")
        func lastMinutes() {
            let newest = Date(timeIntervalSince1970: 1_800_000_600)
            let lines = [
                LogLine(timestamp: newest.addingTimeInterval(-301), text: "just outside", source: .oslog, level: .info),
                LogLine(timestamp: newest.addingTimeInterval(-300), text: "on the boundary", source: .oslog, level: .info),
                LogLine(timestamp: newest.addingTimeInterval(-10), text: "inside", source: .oslog, level: .info),
                LogLine(timestamp: newest, text: "newest", source: .oslog, level: .info)
            ]
            var sut = ConsoleFilter()
            sut.timeRange = .last(minutes: 5)
            let expected = ["on the boundary", "inside", "newest"]

            let actual = sut.apply(to: lines).map(\.text)

            #expect(actual == expected)
        }

        @Test("The time range counts back from the newest line even when an earlier one arrives last")
        func lastMinutesOutOfOrder() {
            let newest = Date(timeIntervalSince1970: 1_800_000_600)
            let lines = [
                LogLine(timestamp: newest, text: "newest", source: .oslog, level: .info),
                LogLine(timestamp: newest.addingTimeInterval(-120), text: "two minutes earlier", source: .stdout, level: .info)
            ]
            var sut = ConsoleFilter()
            sut.timeRange = .last(minutes: 1)
            let expected = ["newest"]

            let actual = sut.apply(to: lines).map(\.text)

            #expect(actual == expected)
        }

        @Test("Since a line passes that line and every later one")
        func since() {
            let start = Date(timeIntervalSince1970: 1_800_000_000)
            let lines = (0 ..< 4).map { LogLine(timestamp: start.addingTimeInterval(Double($0)), text: "line \($0)", source: .oslog, level: .info) }
            var sut = ConsoleFilter()
            sut.timeRange = .since(lines[2].timestamp)
            let expected = ["line 2", "line 3"]

            let actual = sut.apply(to: lines).map(\.text)

            #expect(actual == expected)
        }

        @Test("The time range titles name each preset and the time a range set from a line starts")
        func timeRangeTitles() throws {
            let morning = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 5, hour: 9, minute: 41, second: 2)))
            let expected = ["All", "Last Minute", "Last 5 Minutes", "Last 15 Minutes", "Since 09:41:02.000"]

            let actual = (ConsoleTimeRange.presets + [.since(morning)]).map(\.title)

            #expect(actual == expected)
        }

        @Test("A muted subsystem hides its lines and counts them; a muted category hides that category of its subsystem alone")
        func mutes() {
            let start = Date(timeIntervalSince1970: 1_800_000_000)
            let lines = [
                LogLine(timestamp: start, text: "stdout", source: .stdout, level: .info),
                LogLine(timestamp: start, text: "feed", source: .oslog, level: .info, subsystem: "com.example.feed", category: "net"),
                LogLine(timestamp: start, text: "cart ui", source: .oslog, level: .info, subsystem: "com.example.cart", category: "ui"),
                LogLine(timestamp: start, text: "cart net", source: .oslog, level: .info, subsystem: "com.example.cart", category: "net")
            ]
            var sut = ConsoleFilter()
            sut.mutes = [.subsystem("com.example.feed"), .category("net", subsystem: "com.example.cart")]
            let expected = ["stdout", "cart ui"]
            let expectedCount = 2

            let actual = sut.apply(to: lines).map(\.text)
            let count = sut.mutedCount(in: lines)

            #expect(actual == expected)
            #expect(count == expectedCount)
        }

        @Test("Showing muted lines passes them again and still counts them")
        func showsMuted() {
            let start = Date(timeIntervalSince1970: 1_800_000_000)
            let lines = [
                LogLine(timestamp: start, text: "feed", source: .oslog, level: .info, subsystem: "com.example.feed"),
                LogLine(timestamp: start, text: "cart", source: .oslog, level: .info, subsystem: "com.example.cart")
            ]
            var sut = ConsoleFilter()
            sut.mutes = [.subsystem("com.example.feed")]
            sut.showsMuted = true
            let expected = ["feed", "cart"]

            let actual = sut.apply(to: lines).map(\.text)

            #expect(actual == expected)
            #expect(sut.mutedCount(in: lines) == 1)
        }

        @Test("The muted count leaves out muted lines the level, search or time range hides anyway")
        func mutedCountRespectsOtherFilters() throws {
            let start = Date(timeIntervalSince1970: 1_800_000_000)
            let lines = [
                LogLine(timestamp: start, text: "old feed", source: .oslog, level: .error, subsystem: "com.example.feed"),
                LogLine(timestamp: start.addingTimeInterval(600), text: "feed debug", source: .oslog, level: .debug, subsystem: "com.example.feed"),
                LogLine(timestamp: start.addingTimeInterval(600), text: "feed error", source: .oslog, level: .error, subsystem: "com.example.feed"),
                LogLine(timestamp: start.addingTimeInterval(600), text: "other error", source: .oslog, level: .error, subsystem: "com.example.feed")
            ]
            var sut = ConsoleFilter()
            sut.level = .error
            sut.timeRange = .last(minutes: 1)
            sut.search = try ConsoleSearch("feed", isRegularExpression: false)
            sut.mutes = [.subsystem("com.example.feed")]
            let expected = 2

            let actual = sut.mutedCount(in: lines)

            #expect(actual == expected)
        }

        @Test("The mute choices are each subsystem shown, then each category, sorted, without what's muted or covered")
        func muteChoices() {
            let start = Date(timeIntervalSince1970: 1_800_000_000)
            let lines = [
                LogLine(timestamp: start, text: "stdout", source: .stdout, level: .info),
                LogLine(timestamp: start, text: "a", source: .oslog, level: .info, subsystem: "com.example.feed", category: "net"),
                LogLine(timestamp: start, text: "b", source: .oslog, level: .info, subsystem: "com.example.cart", category: "ui"),
                LogLine(timestamp: start, text: "c", source: .oslog, level: .info, subsystem: "com.example.cart", category: "net"),
                LogLine(timestamp: start, text: "d", source: .oslog, level: .info, subsystem: "com.example.auth"),
                LogLine(timestamp: start, text: "e", source: .oslog, level: .info, subsystem: "com.example.cart", category: "ui")
            ]
            let mutes: [ConsoleMute] = [.subsystem("com.example.feed"), .category("ui", subsystem: "com.example.cart")]
            let expected: [ConsoleMute] = [
                .subsystem("com.example.auth"), .subsystem("com.example.cart"), .category("net", subsystem: "com.example.cart")
            ]

            let actual = ConsoleMute.choices(in: lines, excluding: mutes)

            #expect(actual == expected)
        }

        @Test("A line's actions mute its subsystem and its category, then show from it on; a stdout line offers only the last")
        func lineActions() {
            let time = Date(timeIntervalSince1970: 1_800_000_000)
            let oslog = LogLine(timestamp: time, text: "a", source: .oslog, level: .info, subsystem: "com.example.feed", category: "net")
            let stdout = LogLine(timestamp: time, text: "b", source: .stdout, level: .info)
            let expected: [ConsoleLineAction] = [
                .mute(.subsystem("com.example.feed")), .mute(.category("net", subsystem: "com.example.feed")), .showSince(time)
            ]
            let expectedTitles = ["Mute Subsystem “com.example.feed”", "Mute Category “net”", "Show Since This Line"]

            let actual = ConsoleLineAction.actions(for: oslog)

            #expect(actual == expected)
            #expect(actual.map(\.title) == expectedTitles)
            #expect(ConsoleLineAction.actions(for: stdout) == [.showSince(time)])
        }

        @Test("A line shows its subsystem's last component and its category, or whichever it has, or nothing")
        func shownOrigin() {
            let time = Date(timeIntervalSince1970: 1_800_000_000)
            let both = LogLine(timestamp: time, text: "", source: .oslog, level: .info, subsystem: "com.example.feed", category: "networking")
            let subsystemOnly = LogLine(timestamp: time, text: "", source: .oslog, level: .info, subsystem: "ExampleApp")
            let categoryOnly = LogLine(timestamp: time, text: "", source: .oslog, level: .info, category: "ui")
            let neither = LogLine(timestamp: time, text: "", source: .stdout, level: .info)

            #expect(both.shownOrigin == "feed/networking")
            #expect(subsystemOnly.shownOrigin == "ExampleApp")
            #expect(categoryOnly.shownOrigin == "ui")
            #expect(neither.shownOrigin == nil)
        }
    }
#endif
