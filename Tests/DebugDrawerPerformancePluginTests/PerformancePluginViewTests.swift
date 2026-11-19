// ViewInspector is linked on Apple platforms only, and the views are tested on the Mac.
#if os(macOS)
    import DebugDrawer
    @testable import DebugDrawerPerformancePlugin
    import SwiftUI
    import Testing
    import ViewInspector

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct PerformancePluginViewTests {
        @Test("The plugin's view draws the snapshot: the frame rate, its lowest and average, the frames dropped, the peak and the threads")
        func viewDrawsTheSnapshot() throws {
            let sut = PerformancePluginView(
                transport: DebugDrawerPluginTransport(
                    initial: PerformanceSnapshot(
                        fps: 41, droppedFrames: 7, fpsHistory: [60, 41, 50], footprintMB: 182.4,
                        footprintHistory: [180, 182.4], peakFootprintMB: 240, physicalMemoryMB: 16384,
                        threads: [ThreadCPU(name: "com.example.worker", threadID: 2, cpuUsage: 0.5)]
                    ),
                    snapshots: AsyncStream { $0.finish() },
                    send: { _ in }
                )
            )

            let texts = try sut.inspect().findAll(ViewType.Text.self).map { try $0.string() }

            #expect(texts.contains("41 fps"))
            #expect(texts.contains("Lowest"))
            #expect(texts.contains("50 fps"))
            #expect(texts.contains("7"))
            #expect(texts.contains("240 MB"))
            #expect(texts.contains("com.example.worker"))
        }

        @Test("The HUD readout draws the transport's frame rate and footprint")
        func hudDrawsTheSnapshot() throws {
            let sut = PerformanceHUD(
                transport: DebugDrawerPluginTransport(
                    initial: PerformanceSnapshot(fps: 41, footprintMB: 182.4),
                    snapshots: AsyncStream { $0.finish() },
                    send: { _ in }
                )
            )

            let texts = try sut.inspect().findAll(ViewType.Text.self).map { try $0.string() }

            #expect(texts.contains("41 FPS"))
        }
    }
#endif
