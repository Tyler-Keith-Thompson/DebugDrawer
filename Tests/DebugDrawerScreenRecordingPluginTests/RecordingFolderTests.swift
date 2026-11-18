#if DEBUG
    @testable import DebugDrawerScreenRecordingPlugin
    import Foundation
    import Testing

    @Suite(.timeLimit(.minutes(1)))
    struct RecordingFolderTests {
        @Test("Outside the App Sandbox the folder is Caches/<bundle identifier>/DebugDrawer/Recordings")
        func unsandboxed() {
            let caches = URL(filePath: "/Users/someone/Library/Caches", directoryHint: .isDirectory)
            let expected = "/Users/someone/Library/Caches/com.example.shop/DebugDrawer/Recordings"

            let actual = RecordingFolder.directory(cachesDirectory: caches, isSandboxed: false, bundleIdentifier: "com.example.shop")

            #expect(actual.path == expected)
        }

        @Test("In a sandboxed app, as on iOS, the folder is Caches/DebugDrawer/Recordings")
        func sandboxed() {
            let caches = URL(filePath: "/containers/shop/Library/Caches", directoryHint: .isDirectory)
            let expected = "/containers/shop/Library/Caches/DebugDrawer/Recordings"

            let actual = RecordingFolder.directory(cachesDirectory: caches, isSandboxed: true, bundleIdentifier: "com.example.shop")

            #expect(actual.path == expected)
        }

        @Test("The standard folder is in the app's own Caches folder on a Mac outside the sandbox, and in Caches/DebugDrawer on iOS")
        func standard() {
            #if os(macOS) || targetEnvironment(macCatalyst)
                // The test runner isn't sandboxed.
                let bundleIdentifier = Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName
                let expected = URL.cachesDirectory.appending(path: "\(bundleIdentifier)/DebugDrawer/Recordings").standardizedFileURL.path
            #else
                let expected = URL.cachesDirectory.appending(path: "DebugDrawer/Recordings").standardizedFileURL.path
            #endif

            let actual = RecordingFolder.standard.directory.standardizedFileURL.path

            #expect(actual == expected)
        }

        @Test("A recording is named for when it started, in UTC with - for :, and the folder is created")
        func name() throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let sut = RecordingFolder(directory: directory)
            let expected = "Screen Recording 2025-11-16T10-46-40Z.mov"

            let actual = try sut.url(forRecordingStartedAt: Date(timeIntervalSince1970: 1_763_290_000))

            #expect(actual.lastPathComponent == expected)
            #expect(FileManager.default.fileExists(atPath: directory.path))
        }

        @Test("A second recording of the same second gets \" 2\", a third \" 3\"")
        func unique() throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let sut = RecordingFolder(directory: directory)
            let date = Date(timeIntervalSince1970: 1_763_290_000)
            let expected = [
                "Screen Recording 2025-11-16T10-46-40Z.mov",
                "Screen Recording 2025-11-16T10-46-40Z 2.mov",
                "Screen Recording 2025-11-16T10-46-40Z 3.mov"
            ]

            var actual: [String] = []
            for _ in 0 ..< 3 {
                let url = try sut.url(forRecordingStartedAt: date)
                try Data().write(to: url)
                actual.append(url.lastPathComponent)
            }

            #expect(actual == expected)
        }

        @Test("A folder that can't be created throws writeFailed")
        func uncreatable() throws {
            let file = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: file) }
            try Data().write(to: file)
            let sut = RecordingFolder(directory: file.appending(path: "Recordings"))

            #expect(throws: RecordingFailure.writeFailed) {
                try sut.url(forRecordingStartedAt: Date())
            }
        }

        @Test("The list is the recordings, newest first, with their start from the name and size; other files are left out")
        func recordings() async throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for name in [
                "Screen Recording 2025-11-16T10-46-40Z.mov", "Screen Recording 2025-11-16T10-46-40Z 2.mov",
                "Screen Recording 2025-11-16T10-47-00Z.mov", "notes.txt", "Other.mov"
            ] {
                try Data("12345".utf8).write(to: directory.appending(path: name))
            }
            let sut = RecordingFolder(directory: directory)
            let expectedNames = [
                "Screen Recording 2025-11-16T10-47-00Z.mov", "Screen Recording 2025-11-16T10-46-40Z 2.mov",
                "Screen Recording 2025-11-16T10-46-40Z.mov"
            ]
            let expectedStarts = [1_763_290_020, 1_763_290_000, 1_763_290_000].map { Date(timeIntervalSince1970: $0) }

            let actual = await sut.recordings()

            #expect(actual.map(\.url.lastPathComponent) == expectedNames)
            #expect(actual.map(\.started) == expectedStarts)
            #expect(actual.map(\.byteCount) == [5, 5, 5])
            // Five bytes aren't a movie, so their length can't be read.
            #expect(actual.allSatisfy { $0.duration == nil })
        }

        @Test("A folder that doesn't exist yet lists nothing")
        func missing() async {
            let sut = RecordingFolder(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))

            let actual = await sut.recordings()

            #expect(actual.isEmpty)
        }

        @Test("Pruning keeps the first capacity recordings and deletes the files of the rest")
        func prune() async throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let names = [
                "Screen Recording 2025-11-16T10-46-40Z.mov", "Screen Recording 2025-11-16T10-46-50Z.mov",
                "Screen Recording 2025-11-16T10-47-00Z.mov"
            ]
            for name in names {
                try Data().write(to: directory.appending(path: name))
            }
            let sut = RecordingFolder(directory: directory)
            let recordings = await sut.recordings()

            let kept = sut.prune(recordings, keeping: 1)
            let keptAll = sut.prune(kept, keeping: 5)

            let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            #expect(kept.map(\.url.lastPathComponent) == [names[2]])
            #expect(keptAll == kept)
            #expect(files == [names[2]])
        }

        @Test("A start time reads back from the name it gave, with or without a repeat number; other names give none")
        func startDate() {
            let date = Date(timeIntervalSince1970: 1_763_290_000)
            let name = "Screen Recording \(RecordingFolder.timestamp(of: date))"

            #expect(RecordingFolder.startDate(ofFileNamed: name) == date)
            #expect(RecordingFolder.startDate(ofFileNamed: name + " 2") == date)
            #expect(RecordingFolder.startDate(ofFileNamed: "Screen Recording yesterday") == nil)
            #expect(RecordingFolder.startDate(ofFileNamed: "Movie 2025-11-16T10-46-40Z") == nil)
        }

        @Test("Lengths read as minutes and seconds, hours past the first, never negative")
        func lengths() {
            #expect(Duration.seconds(0).recordingLength == "0:00")
            #expect(Duration.seconds(12.9).recordingLength == "0:12")
            #expect(Duration.seconds(725).recordingLength == "12:05")
            #expect(Duration.seconds(3723).recordingLength == "1:02:03")
            #expect(Duration.seconds(-5).recordingLength == "0:00")
        }

        @Test("A recording's summary is its length and size, or its size alone when the length is unknown")
        func summary() {
            let url = URL(filePath: "/tmp/Screen Recording.mov")
            let timed = Recording(url: url, started: .now, duration: .seconds(12), byteCount: 3_400_000)
            let untimed = Recording(url: url, started: .now, duration: nil, byteCount: 3_400_000)

            #expect(timed.summary == "0:12 · 3.4 MB")
            #expect(untimed.summary == "3.4 MB")
        }
    }
#endif
