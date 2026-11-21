// The capability as a sidecar reaches it: a real DebugDrawerReceiver serving the app-group store, and
// the sidecar's DebugDrawerAppGroupStoreTransport (a debug-build type) reading it from the same
// directory, opening sessions through the sessions' own model. The watched thread is a helper
// thread's run loop (StallingThread), as a test runner's main thread doesn't turn its run loop.
#if DEBUG
    import DebugDrawer
    @testable import DebugDrawerHangDetector
    @testable import DebugDrawerReceiver
    import Foundation
    import Testing

    @MainActor
    @Suite(.serialized, .timeLimit(.minutes(1)))
    struct PerformanceTracesSidecarTests {
        @Test("A hang during a session's recording reaches the sidecar with its main-thread stack, and leaves the store as the session ends")
        func hangReachesSidecar() async throws {
            let root = FileManager.default.temporaryDirectory.appending(path: "PerformanceTracesSidecarTests-\(UUID().uuidString)")
            let store = root.appending(path: "Group/DebugDrawer")
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let receiver = DebugDrawerReceiver(directory: store, sessions: sessions)
            let thread = StallingThread()
            let traces = PerformanceTraces(
                sessions: sessions, hitchThreshold: .milliseconds(50), hangThreshold: .milliseconds(50), limits: .standard,
                now: { Date() }, watchedThread: { (thread.runLoop, thread.sampler) }
            )
            receiver.enable(.performanceTraces(traces))
            try receiver.start()
            defer { receiver.stop() }
            let sidecar = try DebugDrawerAppGroupStoreTransport(directory: AppGroupStoreLayout.appDirectory(inStore: store))
            let sessionControl = try await sidecar.connect(
                toPlugin: DebugDrawerSessions.pluginID, snapshot: DebugDrawerSessionState.self, command: DebugDrawerSessionCommand.self
            )
            let snapshotFile = AppGroupStoreLayout(directory: receiver.appDirectory).snapshotFile(for: PerformanceTraces.pluginID)

            let servedBeforeSession = FileManager.default.fileExists(atPath: snapshotFile.path)
            sessionControl.send(.open(duration: 60))
            // Served once the session is open.
            let recording = try await sidecar.connect(
                toPlugin: PerformanceTraces.pluginID, snapshot: PerformanceTraces.Snapshot.self, command: PerformanceTraces.Command.self
            )
            var arrivals = recording.snapshots().makeAsyncIterator()
            let beforeRecording = await arrivals.next()
            recording.send(.start)
            while let snapshot = await arrivals.next(), !snapshot.isRecording {}
            thread.stall()
            var during: PerformanceTraces.Snapshot?
            while let snapshot = await arrivals.next() {
                if !snapshot.stalls.isEmpty {
                    during = snapshot
                    break
                }
            }
            let fileDuring = (try? Data(contentsOf: snapshotFile)).flatMap(StoreDocument.decoded(from:))?.message.payload
            sessionControl.send(.end)
            for await state in sessionControl.snapshots() where !state.isActive {
                break
            }
            let servedAfterSession = FileManager.default.fileExists(atPath: snapshotFile.path)

            let stall = try #require(during?.stalls.first)
            let lines = stall.frames.enumerated().map { $1.line(index: $0) }
            let decodedDuring = try fileDuring.map { try JSONDecoder().decode(PerformanceTraces.Snapshot.self, from: $0) }
            #expect(thread.finished())
            #expect(!servedBeforeSession)
            #expect(beforeRecording?.isRecording == false)
            #expect(stall.kind == .hang)
            #expect(stall.duration >= .milliseconds(50))
            #expect(lines.contains { $0.contains("semaphore") || $0.contains("ulock") })
            #expect(lines.contains { $0.contains("CFRunLoop") })
            #expect(stall.frames.contains { $0.image != nil && $0.imageUUID != nil && $0.imageOffset != nil })
            #expect(decodedDuring?.stalls == during?.stalls)
            #expect(!servedAfterSession)
            #expect(traces.monitor == nil)
        }

        @Test("A snapshot file a killed launch left is removed as the next launch enables the capability")
        func leftoverRemoved() throws {
            let root = FileManager.default.temporaryDirectory.appending(path: "PerformanceTracesSidecarTests-\(UUID().uuidString)")
            let store = root.appending(path: "Group/DebugDrawer")
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let receiver = DebugDrawerReceiver(directory: store, sessions: sessions)
            let layout = AppGroupStoreLayout(directory: receiver.appDirectory)
            #expect(layout.create())
            let leftover = PerformanceTraces.Snapshot(
                sessionID: UUID(), executable: "Example", hitchThreshold: .milliseconds(100), hangThreshold: .milliseconds(250),
                stalls: [PerformanceTraces.Stall(id: 1, kind: .hang, began: Date(), duration: .seconds(2), frames: [])],
                intervals: [], droppedStalls: 0, droppedIntervals: 0, limits: .standard, exports: []
            )
            let payload = try TransportMessage.payload(leftover)
            let document = StoreDocument(TransportMessage(kind: .snapshot, pluginID: PerformanceTraces.pluginID, payload: payload))
            let snapshotFile = layout.snapshotFile(for: PerformanceTraces.pluginID)
            try layout.write(document.encoded(), to: snapshotFile)
            let existedBefore = FileManager.default.fileExists(atPath: snapshotFile.path)

            receiver.enable(.performanceTraces(PerformanceTraces(sessions: sessions)))

            #expect(existedBefore)
            #expect(!FileManager.default.fileExists(atPath: snapshotFile.path))
        }
    }
#endif
