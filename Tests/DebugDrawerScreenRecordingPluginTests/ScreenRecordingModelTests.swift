#if DEBUG
    @testable import DebugDrawerScreenRecordingPlugin
    import Foundation
    import Testing

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct ScreenRecordingModelTests {
        @Test("Record starts the frame source and records from the moment it was pressed; each frame goes to the writer")
        func start() throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let source = FakeFrameSource()
            var writers: [FakeMovieWriter] = []
            let started = Date(timeIntervalSince1970: 1_763_290_000)
            let sut = ScreenRecordingModel(
                folder: RecordingFolder(directory: directory), capacity: 5, frameSource: source,
                makeWriter: { url in
                    let writer = FakeMovieWriter(url: url)
                    writers.append(writer)
                    return writer
                },
                now: { started }, defaults: try #require(UserDefaults(suiteName: UUID().uuidString))
            )
            let expectedTimes: [TimeInterval] = [10, 10.5]

            sut.start()
            source.send(at: 10)
            source.send(at: 10.5)

            #expect(sut.state == .recording(started: started))
            #expect(source.startedShowingTouches == [false])
            #expect(writers.count == 1)
            #expect(writers.first?.appendedTimes == expectedTimes)
            #expect(writers.first?.url.lastPathComponent == "Screen Recording 2025-11-16T10-46-40Z.mov")
        }

        @Test("Record while recording does nothing: one writer, one start")
        func startTwice() throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let source = FakeFrameSource()
            var writerCount = 0
            let sut = ScreenRecordingModel(
                folder: RecordingFolder(directory: directory), capacity: 5, frameSource: source,
                makeWriter: { url in
                    writerCount += 1
                    return FakeMovieWriter(url: url)
                },
                defaults: try #require(UserDefaults(suiteName: UUID().uuidString))
            )

            sut.start()
            sut.start()

            #expect(writerCount == 1)
            #expect(source.startedShowingTouches.count == 1)
        }

        @Test("Stop stops the frames, saves the movie, lists it first and puts it in the bug report")
        func stop() async throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let source = FakeFrameSource()
            let sut = ScreenRecordingModel(
                folder: RecordingFolder(directory: directory), capacity: 5, frameSource: source,
                makeWriter: { FakeMovieWriter(url: $0) },
                now: { Date(timeIntervalSince1970: 1_763_290_000) },
                defaults: try #require(UserDefaults(suiteName: UUID().uuidString))
            )
            sut.start()
            source.send(at: 1)

            await sut.stop()
            source.send(at: 2)

            let saved = try #require(sut.recordings.first)
            #expect(sut.state == .finished(saved.url))
            #expect(source.stopCount == 1)
            #expect(sut.recordings.count == 1)
            #expect(sut.includedInReport == [saved.id])
            #expect(sut.reportRecordings == [saved])
            #expect(FileManager.default.fileExists(atPath: saved.url.path))
        }

        @Test("While the movie is written the state is finishing and Record does nothing; then it is finished")
        func finishing() async throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let source = FakeFrameSource()
            var writers: [FakeMovieWriter] = []
            let sut = ScreenRecordingModel(
                folder: RecordingFolder(directory: directory), capacity: 5, frameSource: source,
                makeWriter: { url in
                    let writer = FakeMovieWriter(url: url)
                    writer.holdsFinish = true
                    writers.append(writer)
                    return writer
                },
                defaults: try #require(UserDefaults(suiteName: UUID().uuidString))
            )
            sut.start()
            source.send(at: 1)
            let states = sut.$state.values

            let stopping = Task { await sut.stop() }
            for await state in states where state == .finishing {
                break
            }
            sut.start()
            let duringFinish = sut.state
            writers.first?.openGate()
            await stopping.value

            #expect(duringFinish == .finishing)
            #expect(writers.count == 1)
            #expect(source.startedShowingTouches.count == 1)
            #expect(sut.state == .finished(try #require(sut.recordings.first).url))
        }

        @Test("A recording stopped before its first frame fails with noFrames and leaves no file")
        func noFrames() async throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let sut = ScreenRecordingModel(
                folder: RecordingFolder(directory: directory), capacity: 5, frameSource: FakeFrameSource(),
                makeWriter: { url in
                    let writer = FakeMovieWriter(url: url)
                    writer.failure = .noFrames
                    return writer
                },
                defaults: try #require(UserDefaults(suiteName: UUID().uuidString))
            )
            sut.start()

            await sut.stop()

            let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            #expect(sut.state == .failed(.noFrames))
            #expect(sut.recordings.isEmpty)
            #expect(files.isEmpty)
        }

        @Test("A movie that can't be written fails with writeFailed, and Record can start again")
        func writeFailed() async throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let source = FakeFrameSource()
            let sut = ScreenRecordingModel(
                folder: RecordingFolder(directory: directory), capacity: 5, frameSource: source,
                makeWriter: { url in
                    let writer = FakeMovieWriter(url: url)
                    writer.failure = .writeFailed
                    return writer
                },
                defaults: try #require(UserDefaults(suiteName: UUID().uuidString))
            )
            sut.start()
            source.send(at: 1)
            await sut.stop()

            let failed = sut.state
            sut.start()

            #expect(failed == .failed(.writeFailed))
            #expect(sut.state.isRecording)
        }

        @Test("With no window to record, Record fails with noWindow and makes no writer's file")
        func noWindow() throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let source = FakeFrameSource()
            source.failure = .noWindow
            let sut = ScreenRecordingModel(
                folder: RecordingFolder(directory: directory), capacity: 5, frameSource: source,
                makeWriter: { FakeMovieWriter(url: $0) },
                defaults: try #require(UserDefaults(suiteName: UUID().uuidString))
            )

            sut.start()

            let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
            #expect(sut.state == .failed(.noWindow))
            #expect(files.isEmpty)
        }

        @Test("Stop when not recording does nothing")
        func stopIdle() async throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            let source = FakeFrameSource()
            let sut = ScreenRecordingModel(
                folder: RecordingFolder(directory: directory), capacity: 5, frameSource: source,
                makeWriter: { FakeMovieWriter(url: $0) },
                defaults: try #require(UserDefaults(suiteName: UUID().uuidString))
            )

            await sut.stop()

            #expect(sut.state == .idle)
            #expect(source.stopCount == 0)
        }

        @Test("Saving past the capacity deletes the oldest recordings; the newest is the one in the report")
        func capacity() async throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let source = FakeFrameSource()
            var clock = Date(timeIntervalSince1970: 1_763_290_000)
            let sut = ScreenRecordingModel(
                folder: RecordingFolder(directory: directory), capacity: 2, frameSource: source,
                makeWriter: { FakeMovieWriter(url: $0) },
                now: { clock },
                defaults: try #require(UserDefaults(suiteName: UUID().uuidString))
            )
            let expected = ["Screen Recording 2025-11-16T10-47-00Z.mov", "Screen Recording 2025-11-16T10-46-50Z.mov"]

            for _ in 0 ..< 3 {
                sut.start()
                source.send(at: 1)
                await sut.stop()
                clock += 10
            }

            let files = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted(by: >)
            #expect(sut.recordings.map(\.url.lastPathComponent) == expected)
            #expect(files == expected)
            #expect(sut.reportRecordings.map(\.url.lastPathComponent) == [expected[0]])
        }

        @Test("Delete removes the file, the row and its place in the report")
        func delete() async throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let source = FakeFrameSource()
            let sut = ScreenRecordingModel(
                folder: RecordingFolder(directory: directory), capacity: 5, frameSource: source,
                makeWriter: { FakeMovieWriter(url: $0) },
                defaults: try #require(UserDefaults(suiteName: UUID().uuidString))
            )
            sut.start()
            source.send(at: 1)
            await sut.stop()
            let recording = try #require(sut.recordings.first)

            sut.delete(recording)

            #expect(sut.recordings.isEmpty)
            #expect(sut.includedInReport.isEmpty)
            #expect(sut.reportRecordings.isEmpty)
            #expect(sut.state == .idle)
            #expect(!FileManager.default.fileExists(atPath: recording.url.path))
        }

        @Test("A recording can be taken out of the report and added back; the report lists them newest first")
        func includeInReport() async throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let source = FakeFrameSource()
            var clock = Date(timeIntervalSince1970: 1_763_290_000)
            let sut = ScreenRecordingModel(
                folder: RecordingFolder(directory: directory), capacity: 5, frameSource: source,
                makeWriter: { FakeMovieWriter(url: $0) },
                now: { clock },
                defaults: try #require(UserDefaults(suiteName: UUID().uuidString))
            )
            for _ in 0 ..< 2 {
                sut.start()
                source.send(at: 1)
                await sut.stop()
                clock += 10
            }
            let newest = sut.recordings[0]
            let oldest = sut.recordings[1]

            sut.setIncludedInReport(true, for: oldest)
            let both = sut.reportRecordings
            sut.setIncludedInReport(false, for: newest)

            #expect(both == [newest, oldest])
            #expect(sut.reportRecordings == [oldest])
        }

        @Test("Show Touches is off unless turned on, starts recordings with touches, and is remembered")
        func showsTouches() throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
            let source = FakeFrameSource()
            let sut = ScreenRecordingModel(
                folder: RecordingFolder(directory: directory), capacity: 5, frameSource: source,
                makeWriter: { FakeMovieWriter(url: $0) }, defaults: defaults
            )
            let initial = sut.showsTouches

            sut.showsTouches = true
            sut.start()
            let reloaded = ScreenRecordingModel(
                folder: RecordingFolder(directory: directory), capacity: 5, frameSource: FakeFrameSource(),
                makeWriter: { FakeMovieWriter(url: $0) }, defaults: defaults
            )

            #expect(!initial)
            #expect(source.startedShowingTouches == [true])
            #expect(reloaded.showsTouches)
        }

        @Test("The HUD's toggle starts a recording, and stops it while it records")
        func toggle() async throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let source = FakeFrameSource()
            let sut = ScreenRecordingModel(
                folder: RecordingFolder(directory: directory), capacity: 5, frameSource: source,
                makeWriter: { FakeMovieWriter(url: $0) },
                defaults: try #require(UserDefaults(suiteName: UUID().uuidString))
            )

            sut.toggle()
            let afterFirst = sut.state.isRecording
            source.send(at: 1)
            let states = sut.$state.values
            sut.toggle()
            for await state in states {
                if case .finished = state { break }
            }

            #expect(afterFirst)
            #expect(source.stopCount == 1)
            #expect(sut.recordings.count == 1)
        }

        @Test("Loading lists the recordings saved before, newest first, keeps the newest capacity, and includes the newest in the report")
        func load() async throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let names = [
                "Screen Recording 2025-11-16T10-46-40Z.mov", "Screen Recording 2025-11-16T10-46-50Z.mov",
                "Screen Recording 2025-11-16T10-47-00Z.mov"
            ]
            for name in names {
                try Data("movie".utf8).write(to: directory.appending(path: name))
            }
            let sut = ScreenRecordingModel(
                folder: RecordingFolder(directory: directory), capacity: 2, frameSource: FakeFrameSource(),
                makeWriter: { FakeMovieWriter(url: $0) },
                defaults: try #require(UserDefaults(suiteName: UUID().uuidString))
            )

            await sut.load()

            #expect(sut.recordings.map(\.url.lastPathComponent) == [names[2], names[1]])
            #expect(sut.reportRecordings.map(\.url.lastPathComponent) == [names[2]])
            #expect(!FileManager.default.fileExists(atPath: directory.appending(path: names[0]).path))
        }
    }
#endif
