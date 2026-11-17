#if DEBUG
    @testable import DebugDrawerConsolePlugin
    import Foundation
    import Testing

    // Lines reach the store through an earlier session shown under Previous, which shows them at
    // once; captured lines arrive through the store's batching, on a timer the tests can't steer.
    @MainActor
    @Suite
    struct ConsoleMuteTests {
        @Test("Muting a subsystem hides its lines, and the mute holds in a new store over the same storage")
        func muteSurvivesANewStore() throws {
            let storage = FakeConsoleMuteStorage()
            let header = #"{"debugDrawerConsoleSession":1,"started":"2027-01-15T08:00:00.000Z","app":"Shop","appVersion":""}"#
            let rows = [
                #"{"level":"info","source":"oslog","subsystem":"com.example.feed","category":"net","text":"Feed","time":"2027-01-15T08:00:01.000Z"}"#,
                #"{"level":"info","source":"oslog","subsystem":"com.example.cart","category":"ui","text":"Cart","time":"2027-01-15T08:00:02.000Z"}"#,
                #"{"level":"info","source":"stdout","text":"printed","time":"2027-01-15T08:00:03.000Z"}"#
            ]
            let data = Data(([header] + rows).joined(separator: "\n").utf8)
            let summary = try #require(ConsoleSessionSummary(ConsoleSessionFile(
                name: ConsoleSessionSummary.name(started: Date(timeIntervalSince1970: 1_800_000_000), id: UUID()), byteCount: data.count
            )))
            let log = ConsoleSessionLog(summary: summary, data: data)
            let first = ConsoleLogStore(muteStorage: storage)
            first.showPrevious(log)
            let expected = ["Cart", "printed"]

            first.mute(.subsystem("com.example.feed"))
            let sut = ConsoleLogStore(muteStorage: storage)
            sut.showPrevious(log)
            let actual = sut.shownLines.map(\.text)

            #expect(first.shownLines.map(\.text) == expected)
            #expect(first.mutedCount == 1)
            #expect(sut.filter.mutes == [.subsystem("com.example.feed")])
            #expect(actual == expected)
            #expect(sut.mutedCount == 1)
        }

        @Test("Mutes saved to the file in Application Support's place read back in a new store")
        func muteSurvivesARelaunchOnDisk() throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            defer { try? FileManager.default.removeItem(at: directory) }
            let first = ConsoleLogStore(muteStorage: _ConsoleMuteStorage(directory: directory))
            let expected: [ConsoleMute] = [.subsystem("com.example.feed"), .category("ui", subsystem: "com.example.cart")]

            first.mute(.subsystem("com.example.feed"))
            first.mute(.category("ui", subsystem: "com.example.cart"))
            let sut = ConsoleLogStore(muteStorage: _ConsoleMuteStorage(directory: directory))

            #expect(sut.filter.mutes == expected)
            #expect(sut.muteIssue == nil)
            #expect(FileManager.default.fileExists(atPath: directory.appending(path: "muted.json").path(percentEncoded: false)))
        }

        @Test("Unmuting shows the lines again and is saved; muting twice adds one mute")
        func unmute() throws {
            let storage = FakeConsoleMuteStorage()
            let header = #"{"debugDrawerConsoleSession":1,"started":"2027-01-15T08:00:00.000Z","app":"Shop","appVersion":""}"#
            let rows = [
                #"{"level":"info","source":"oslog","subsystem":"com.example.feed","text":"Feed loaded","time":"2027-01-15T08:00:01.000Z"}"#
            ]
            let data = Data(([header] + rows).joined(separator: "\n").utf8)
            let summary = try #require(ConsoleSessionSummary(ConsoleSessionFile(
                name: ConsoleSessionSummary.name(started: Date(timeIntervalSince1970: 1_800_000_000), id: UUID()), byteCount: data.count
            )))
            let log = ConsoleSessionLog(summary: summary, data: data)
            let sut = ConsoleLogStore(muteStorage: storage)
            sut.showPrevious(log)

            sut.mute(.subsystem("com.example.feed"))
            sut.mute(.subsystem("com.example.feed"))
            let muted = sut.filter.mutes
            sut.unmute(.subsystem("com.example.feed"))
            let relaunched = ConsoleLogStore(muteStorage: storage)

            #expect(muted == [.subsystem("com.example.feed")])
            #expect(sut.shownLines.map(\.text) == ["Feed loaded"])
            #expect(relaunched.filter.mutes.isEmpty)
        }

        @Test("Unmute All forgets every mute and stops showing muted lines")
        func unmuteAll() {
            let storage = FakeConsoleMuteStorage()
            let sut = ConsoleLogStore(muteStorage: storage)
            sut.mute(.subsystem("com.example.feed"))
            sut.mute(.category("ui", subsystem: "com.example.cart"))
            sut.showsMuted = true

            sut.unmuteAll()

            #expect(sut.filter.mutes.isEmpty)
            #expect(!sut.showsMuted)
            #expect(ConsoleLogStore(muteStorage: storage).filter.mutes.isEmpty)
        }

        @Test("Show passes the muted lines for now, without forgetting the mute")
        func showMuted() throws {
            let header = #"{"debugDrawerConsoleSession":1,"started":"2027-01-15T08:00:00.000Z","app":"Shop","appVersion":""}"#
            let rows = [
                #"{"level":"info","source":"oslog","subsystem":"com.example.feed","text":"Feed loaded","time":"2027-01-15T08:00:01.000Z"}"#
            ]
            let data = Data(([header] + rows).joined(separator: "\n").utf8)
            let summary = try #require(ConsoleSessionSummary(ConsoleSessionFile(
                name: ConsoleSessionSummary.name(started: Date(timeIntervalSince1970: 1_800_000_000), id: UUID()), byteCount: data.count
            )))
            let log = ConsoleSessionLog(summary: summary, data: data)
            let sut = ConsoleLogStore(muteStorage: FakeConsoleMuteStorage())
            sut.showPrevious(log)
            sut.mute(.subsystem("com.example.feed"))

            sut.showsMuted = true

            #expect(sut.shownLines.map(\.text) == ["Feed loaded"])
            #expect(sut.mutedCount == 1)
            #expect(sut.filter.mutes == [.subsystem("com.example.feed")])
        }

        @Test("A mute that can't be saved still applies, and the store says it lasts until the app quits")
        func notSaved() {
            let storage = FakeConsoleMuteStorage()
            storage.failsWriting = true
            let sut = ConsoleLogStore(muteStorage: storage)

            sut.mute(.subsystem("com.example.feed"))

            #expect(sut.filter.mutes == [.subsystem("com.example.feed")])
            #expect(sut.muteIssue == .notSaved)
            #expect(storage.data == nil)
        }

        @Test("A saved file that isn't the format mutes nothing and says so")
        func unreadableFile() {
            let sut = ConsoleLogStore(muteStorage: FakeConsoleMuteStorage(data: Data("not json".utf8)))

            #expect(sut.filter.mutes.isEmpty)
            #expect(sut.muteIssue == .unreadable)
        }

        @Test("A saved file of a later format mutes nothing and names the format")
        func laterFormat() {
            let data = Data(#"{"version":2,"mutes":[{"subsystem":"com.example.feed"}]}"#.utf8)

            let sut = ConsoleLogStore(muteStorage: FakeConsoleMuteStorage(data: data))

            #expect(sut.filter.mutes.isEmpty)
            #expect(sut.muteIssue == .unsupportedVersion(2))
        }

        @Test("The file keeps subsystems and categories in order, and skips an entry with no subsystem")
        func fileRoundTrip() throws {
            let mutes: [ConsoleMute] = [.category("ui", subsystem: "com.example.cart"), .subsystem("com.example.feed")]
            let handEdited = Data(#"{"version":1,"mutes":[{"subsystem":""},{"subsystem":"com.example.auth","category":""}]}"#.utf8)

            let actual = try ConsoleMuteListFile.decode(ConsoleMuteListFile.encode(mutes))
            let edited = try ConsoleMuteListFile.decode(handEdited)

            #expect(actual == mutes)
            #expect(edited == [.subsystem("com.example.auth")])
        }
    }
#endif
