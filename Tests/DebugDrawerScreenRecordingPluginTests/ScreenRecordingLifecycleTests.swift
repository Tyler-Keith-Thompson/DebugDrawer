#if DEBUG
    @testable import DebugDrawer
    @testable import DebugDrawerScreenRecordingPlugin
    import Foundation
    import Testing

    @MainActor
    @Suite("Screen Recording install and uninstall", .timeLimit(.minutes(1)))
    struct ScreenRecordingLifecycleTests {
        private func makeDrawer(_ suite: String) throws -> DebugDrawer {
            try DebugDrawer(defaults: #require(UserDefaults(suiteName: suite)))
        }

        private func makeModel(directory: URL, source: FakeFrameSource) throws -> ScreenRecordingModel {
            try ScreenRecordingModel(
                folder: RecordingFolder(directory: directory), capacity: 5, frameSource: source,
                makeWriter: { FakeMovieWriter(url: $0) },
                now: { Date(timeIntervalSince1970: 1_763_290_000) },
                defaults: #require(UserDefaults(suiteName: UUID().uuidString))
            )
        }

        @Test("Unregistering the plugin while it records removes it, stops the frames, and saves the movie without listing it")
        func uninstallWhileRecording() async throws {
            let suite = "ScreenRecordingLifecycleTests.\(UUID().uuidString)"
            defer { UserDefaults().removePersistentDomain(forName: suite) }
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let drawer = try makeDrawer(suite)
            let source = FakeFrameSource()
            let model = try makeModel(directory: directory, source: source)
            let sut = ScreenRecordingPlugin(model: model)
            drawer.registerGlobal(sut)
            model.start()
            source.send(at: 1)

            drawer.unregisterGlobal(id: sut.id)
            let stopsOnUninstall = source.stopCount
            source.send(at: 2)
            await model.savingAfterUninstall?.value

            let saved = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            #expect(!drawer.globalPlugins.contains { $0.id == sut.id })
            #expect(stopsOnUninstall == 1)
            #expect(model.state == .idle)
            #expect(model.recordings.isEmpty)
            #expect(saved == ["Screen Recording 2025-11-16T10-46-40Z.mov"])
        }

        @Test("Unregistering drops the list and the report's choice, keeping the recordings on disk; installing again lists them")
        func uninstallDropsTheList() async throws {
            let suite = "ScreenRecordingLifecycleTests.\(UUID().uuidString)"
            defer { UserDefaults().removePersistentDomain(forName: suite) }
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let drawer = try makeDrawer(suite)
            let source = FakeFrameSource()
            let model = try makeModel(directory: directory, source: source)
            let sut = ScreenRecordingPlugin(model: model)
            drawer.registerGlobal(sut)
            model.start()
            source.send(at: 1)
            await model.stop()
            let recording = try #require(model.recordings.first)

            drawer.unregisterGlobal(id: sut.id)
            let isDropped = model.recordings.isEmpty && model.includedInReport.isEmpty && model.state == .idle
            let isOnDisk = FileManager.default.fileExists(atPath: recording.url.path)
            let listed = model.$recordings.values
            drawer.registerGlobal(sut)
            var relisted: [Recording] = []
            for await recordings in listed where !recordings.isEmpty {
                relisted = recordings
                break
            }

            #expect(isDropped)
            #expect(isOnDisk)
            #expect(relisted.map(\.id) == [recording.id])
        }

        @Test("Uninstalling twice stops the frames once")
        func uninstallTwice() throws {
            let suite = "ScreenRecordingLifecycleTests.\(UUID().uuidString)"
            defer { UserDefaults().removePersistentDomain(forName: suite) }
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let drawer = try makeDrawer(suite)
            let source = FakeFrameSource()
            let model = try makeModel(directory: directory, source: source)
            let sut = ScreenRecordingPlugin(model: model)
            drawer.registerGlobal(sut)
            model.start()

            sut.uninstall(from: drawer)
            sut.uninstall(from: drawer)

            #expect(source.stopCount == 1)
            #expect(model.isUninstalled)
        }

        @Test("In two drawers a recording goes on until the last one uninstalls the plugin")
        func twoDrawers() throws {
            let suite = "ScreenRecordingLifecycleTests.\(UUID().uuidString)"
            defer { UserDefaults().removePersistentDomain(forName: suite) }
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let first = try makeDrawer(suite)
            let second = try makeDrawer(suite)
            let source = FakeFrameSource()
            let model = try makeModel(directory: directory, source: source)
            let sut = ScreenRecordingPlugin(model: model)
            first.registerGlobal(sut)
            second.registerGlobal(sut)
            model.start()

            first.unregisterGlobal(id: sut.id)
            let isRecordingWithOneLeft = model.state.isRecording
            second.unregisterGlobal(id: sut.id)

            #expect(isRecordingWithOneLeft)
            #expect(source.stopCount == 1)
        }
    }
#endif
