// The README's production performance traces example, verbatim, so the README cannot drift from the
// code.
#if DEBUG
    import DebugDrawer
    import DebugDrawerHangDetector
    import DebugDrawerReceiver
    import Foundation
    import Testing

    @MainActor
    final class ProductionPerformance {
        let sessions = DebugDrawerSessions(maximumDuration: 15 * 60)
        let traces: PerformanceTraces
        let receiver: DebugDrawerReceiver

        init(container: URL) throws {
            traces = PerformanceTraces(sessions: sessions)
            receiver = DebugDrawerReceiver(directory: container.appending(path: "DebugDrawer"), sessions: sessions)
            receiver.enable(.performanceTraces(traces))
            try receiver.start()
        }

        func loadFeed(from url: URL) async throws -> Data {
            let interval = traces.beginInterval("Load feed")
            defer { traces.endInterval(interval) }
            return try await URLSession.shared.data(from: url).0
        }
    }

    @MainActor
    @Suite("README examples")
    struct PerformanceTracesREADMETests {
        @Test(
            "Production builds: hangs and signposts: the capability is served, not recording, and nothing runs until a sidecar starts it",
            .timeLimit(.minutes(1))
        )
        func productionPerformanceTraces() async throws {
            let container = FileManager.default.temporaryDirectory.appending(path: "READMEPerformanceTraces-\(UUID().uuidString)")
            let performance = try ProductionPerformance(container: container)
            defer { performance.receiver.stop() }
            let appDirectory = AppGroupStoreLayout.appDirectory(inStore: container.appending(path: "DebugDrawer"))

            let sidecar = try DebugDrawerAppGroupStoreTransport(directory: appDirectory)
            let traces = try await sidecar.connect(
                toPlugin: PerformanceTraces.pluginID, snapshot: PerformanceTraces.Snapshot.self, command: PerformanceTraces.Command.self
            )

            #expect(performance.receiver.enabledCapabilities == [PerformanceTraces.pluginID])
            #expect(!traces.snapshot.isRecording)
            #expect(traces.snapshot.hitchThreshold == PerformanceTraces.defaultHitchThreshold)
            #expect(traces.snapshot.hangThreshold == PerformanceTraces.defaultHangThreshold)
            #expect(performance.traces.monitor == nil)
        }
    }
#endif
