#if DEBUG
    @testable import DebugDrawerConsolePlugin
    import Foundation
    import Testing

    // Captured lines reach `lines` through the store's batching, so each test waits for the
    // published list to show the last line it sent.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct ConsoleCaptureBoundsTests {
        @Test("At capacity the console keeps taking new lines, drops the oldest and counts them")
        func countBound() async {
            let sut = ConsoleLogStore(muteStorage: FakeConsoleMuteStorage())
            sut.capacity = 3
            let expected = ["c", "d", "e"]

            for text in ["a", "b", "c", "d", "e"] {
                sut.ingest(LogLine(timestamp: Date(timeIntervalSince1970: 1_800_000_000), text: text, source: .stdout, level: .info))
            }
            for await _ in sut.$lines.first(where: { $0.last?.text == "e" }).values {}

            #expect(sut.lines.map(\.text) == expected)
            #expect(sut.droppedLineCount == 2)
        }

        @Test("Past byteCapacity the oldest lines go until the kept text fits")
        func byteBound() async {
            let sut = ConsoleLogStore(muteStorage: FakeConsoleMuteStorage())
            sut.byteCapacity = 10
            let expected = ["bbbb", "cccc"]

            for text in ["aaaa", "bbbb", "cccc"] {
                sut.ingest(LogLine(timestamp: Date(timeIntervalSince1970: 1_800_000_000), text: text, source: .stdout, level: .info))
            }
            for await _ in sut.$lines.first(where: { $0.last?.text == "cccc" }).values {}

            #expect(sut.lines.map(\.text) == expected)
            #expect(sut.droppedLineCount == 1)
        }

        @Test("Clearing forgets the lines and how many were dropped")
        func clear() async {
            let sut = ConsoleLogStore(muteStorage: FakeConsoleMuteStorage())
            sut.capacity = 1
            for text in ["a", "b"] {
                sut.ingest(LogLine(timestamp: Date(timeIntervalSince1970: 1_800_000_000), text: text, source: .stdout, level: .info))
            }
            for await _ in sut.$lines.first(where: { $0.last?.text == "b" }).values {}

            sut.clear()

            #expect(sut.lines.isEmpty)
            #expect(sut.droppedLineCount == 0)
        }

        @Test("Lowering capacity drops the oldest lines now, and counts them")
        func loweringCapacity() async {
            let sut = ConsoleLogStore(muteStorage: FakeConsoleMuteStorage())
            for text in ["a", "b", "c"] {
                sut.ingest(LogLine(timestamp: Date(timeIntervalSince1970: 1_800_000_000), text: text, source: .stdout, level: .info))
            }
            for await _ in sut.$lines.first(where: { $0.last?.text == "c" }).values {}

            sut.capacity = 1

            #expect(sut.lines.map(\.text) == ["c"])
            #expect(sut.droppedLineCount == 2)
        }
    }
#endif
