#if DEBUG
    @testable import DebugDrawerConsolePlugin
    import Foundation
    import Testing

    @Suite
    struct ConsoleLogLineMetadataTests {
        @Test("A line shows its metadata as key=value fields sorted by key, a space between")
        func shownFields() {
            let line = LogLine(
                timestamp: Date(timeIntervalSince1970: 0), text: "Payment declined", source: .sink, level: .error,
                metadata: ["user": "7", "order": "1042", "card": "visa"]
            )
            let expected = "card=visa order=1042 user=7"

            let actual = line.shownMetadata

            #expect(actual == expected)
        }

        @Test("A line with one field shows just that field")
        func oneField() {
            let line = LogLine(timestamp: Date(timeIntervalSince1970: 0), text: "a", source: .sink, level: .info, metadata: ["order": "1042"])
            let expected = "order=1042"

            let actual = line.shownMetadata

            #expect(actual == expected)
        }

        @Test("A text search matches a line by a metadata value, and by a key")
        func textSearchMatchesMetadata() throws {
            let lines = [
                LogLine(
                    timestamp: Date(timeIntervalSince1970: 0), text: "Payment declined", source: .sink, level: .error, metadata: ["order": "1042"]
                ),
                LogLine(timestamp: Date(timeIntervalSince1970: 1), text: "Cart opened", source: .sink, level: .info, metadata: ["cart": "9"])
            ]
            var byValue = ConsoleFilter()
            byValue.search = try ConsoleSearch("1042", isRegularExpression: false)
            var byKey = ConsoleFilter()
            byKey.search = try ConsoleSearch("CART", isRegularExpression: false)
            var byField = ConsoleFilter()
            byField.search = try ConsoleSearch("order=10", isRegularExpression: false)

            let actualByValue = byValue.apply(to: lines).map(\.text)
            let actualByKey = byKey.apply(to: lines).map(\.text)
            let actualByField = byField.apply(to: lines).map(\.text)

            #expect(actualByValue == ["Payment declined"])
            #expect(actualByKey == ["Cart opened"])
            #expect(actualByField == ["Payment declined"])
        }

        @Test("A regular expression anchored on a whole metadata value matches it, and no line whose value only contains it")
        func patternMatchesWholeValue() throws {
            let lines = [
                LogLine(timestamp: Date(timeIntervalSince1970: 0), text: "a", source: .sink, level: .info, metadata: ["order": "1042"]),
                LogLine(timestamp: Date(timeIntervalSince1970: 1), text: "b", source: .sink, level: .info, metadata: ["order": "10420"])
            ]
            var sut = ConsoleFilter()
            sut.search = try ConsoleSearch("^1042$", isRegularExpression: true)

            let actual = sut.apply(to: lines).map(\.text)

            #expect(actual == ["a"])
        }

        @Test("A search that matches neither the text nor the metadata hides the line")
        func searchMisses() throws {
            let lines = [
                LogLine(
                    timestamp: Date(timeIntervalSince1970: 0), text: "Payment declined", source: .sink, level: .error, metadata: ["order": "1042"]
                )
            ]
            var sut = ConsoleFilter()
            sut.search = try ConsoleSearch("9999", isRegularExpression: false)

            let actual = sut.apply(to: lines)

            #expect(actual.isEmpty)
        }

        @Test("Muting a sink line's subsystem hides it, as for an os_log line")
        func muteSinkSubsystem() {
            let lines = [
                LogLine(timestamp: Date(timeIntervalSince1970: 0), text: "a", source: .sink, level: .info, subsystem: "com.example.shop"),
                LogLine(timestamp: Date(timeIntervalSince1970: 1), text: "b", source: .sink, level: .info, subsystem: "com.example.feed")
            ]
            var sut = ConsoleFilter()
            sut.mutes = [.subsystem("com.example.shop")]

            let actual = sut.apply(to: lines).map(\.text)

            #expect(actual == ["b"])
        }

        @Test("Copy All puts the metadata after the text")
        func copiedText() {
            let lines = [
                LogLine(
                    timestamp: Date(timeIntervalSince1970: 0), text: "Payment declined", source: .sink, level: .error,
                    subsystem: "com.example.shop", category: "checkout", metadata: ["user": "7", "order": "1042"]
                ),
                LogLine(timestamp: Date(timeIntervalSince1970: 0), text: "printed", source: .stdout, level: .info)
            ]
            let expected = ["ERR [com.example.shop/checkout] Payment declined order=1042 user=7", "printed"]

            let actual = lines.copiedText.split(separator: "\n").map { String($0.split(separator: " ", maxSplits: 1)[1]) }

            #expect(actual == expected)
        }

        @Test("A session line writes the metadata as an object, and reads it back with the sink as the source")
        func sessionRoundTrip() throws {
            let line = LogLine(
                timestamp: Date(timeIntervalSince1970: 1_800_000_000), text: "Payment declined", source: .sink, level: .error,
                subsystem: "com.example.shop", metadata: ["order": "1042", "user": "7"]
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            let data = try encoder.encode(ConsoleSessionLine(line))
            let expectedJSON = #"{"level":"error","metadata":{"order":"1042","user":"7"},"source":"sink","subsystem":"com.example.shop","#
                + #""text":"Payment declined","time":"2027-01-15T08:00:00.000Z"}"#

            let actual = try #require(try JSONDecoder().decode(ConsoleSessionLine.self, from: data).logLine)

            #expect(String(bytes: data, encoding: .utf8) == expectedJSON)
            #expect(actual.metadata == ["order": "1042", "user": "7"])
            #expect(actual.source == .sink)
            #expect(actual.subsystem == "com.example.shop")
        }

        @Test("A session line written without metadata reads with none")
        func sessionLineWithoutMetadata() throws {
            let data = Data(#"{"level":"info","source":"oslog","text":"Feed loaded","time":"2027-01-15T08:00:01.000Z"}"#.utf8)

            let actual = try #require(try JSONDecoder().decode(ConsoleSessionLine.self, from: data).logLine)

            #expect(actual.metadata.isEmpty)
        }
    }
#endif
