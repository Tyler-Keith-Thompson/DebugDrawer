#if DEBUG
    @testable import DebugDrawerPerformancePlugin
    import Foundation
    import Testing

    /// Stands in for the display link and the 1 s timer: records starts and stops, and delivers
    /// the frames and ticks a test hands it.
    @MainActor
    private final class FakePerformanceSampler: PerformanceSampler {
        private(set) var starts = 0
        private(set) var stops = 0
        private var frame: (@MainActor (TimeInterval, TimeInterval) -> Void)?
        private var tick: (@MainActor () -> Void)?

        var isRunning: Bool {
            frame != nil
        }

        func start(
            frame: @escaping @MainActor (TimeInterval, TimeInterval) -> Void,
            tick: @escaping @MainActor () -> Void
        ) {
            starts += 1
            self.frame = frame
            self.tick = tick
        }

        func stop() {
            stops += 1
            frame = nil
            tick = nil
        }

        func deliverFrame(at timestamp: TimeInterval, duration: TimeInterval) {
            frame?(timestamp, duration)
        }

        func deliverTick() {
            tick?()
        }
    }

    private struct NoThreads: ThreadSampler {
        func sample() -> [ThreadCPU] {
            []
        }
    }

    @MainActor
    @Suite("Performance sampling")
    struct PerformanceSamplingTests {
        @Test("Nothing samples until a view shows the numbers")
        func idleUntilShown() {
            let sampler = FakePerformanceSampler()

            let sut = PerformanceMonitor(sampler: sampler, threadSampler: NoThreads())

            #expect(sampler.starts == 0)
            #expect(!sut.isMonitoring)
        }

        @Test("Sampling starts on the first viewer and stops after the last one leaves")
        func referenceCounted() {
            let sampler = FakePerformanceSampler()
            let sut = PerformanceMonitor(sampler: sampler, threadSampler: NoThreads())

            sut.addViewer()
            sut.addViewer()
            sut.removeViewer()
            let startsWhileOneViewerRemains = sampler.starts
            let runningWhileOneViewerRemains = sampler.isRunning
            sut.removeViewer()

            #expect(startsWhileOneViewerRemains == 1)
            #expect(runningWhileOneViewerRemains)
            #expect(sampler.stops == 1)
            #expect(!sampler.isRunning)
            #expect(!sut.isMonitoring)
        }

        @Test("A viewer removed with none counted stops nothing and starts nothing later on its own")
        func unbalancedRemoval() {
            let sampler = FakePerformanceSampler()
            let sut = PerformanceMonitor(sampler: sampler, threadSampler: NoThreads())

            sut.removeViewer()
            sut.addViewer()

            #expect(sampler.stops == 0)
            #expect(sampler.starts == 1)
            #expect(sut.isMonitoring)
        }

        @Test("A 500 ms gap between frames shows as 29 dropped frames and 31 fps")
        func gapDropsFrames() {
            let sampler = FakePerformanceSampler()
            let sut = PerformanceMonitor(sampler: sampler, threadSampler: NoThreads())
            let frameDuration: TimeInterval = 1.0 / 60
            sut.addViewer()
            for index in 0 ... 15 {
                sampler.deliverFrame(at: TimeInterval(index) * frameDuration, duration: frameDuration)
            }
            for index in 0 ... 15 {
                sampler.deliverFrame(at: 0.75 + TimeInterval(index) * frameDuration, duration: frameDuration)
            }

            sampler.deliverTick()

            #expect(sut.droppedFrames == 29)
            #expect(sut.fps == 31)
            #expect(sut.maximumFPS == 60)
        }

        @Test("The gap from the last frame of one second to the first of the next counts")
        func gapAcrossTicks() {
            let sampler = FakePerformanceSampler()
            let sut = PerformanceMonitor(sampler: sampler, threadSampler: NoThreads())
            let frameDuration: TimeInterval = 1.0 / 60
            sut.addViewer()
            sampler.deliverFrame(at: 10, duration: frameDuration)
            sampler.deliverFrame(at: 10 + frameDuration, duration: frameDuration)
            sampler.deliverTick()
            sampler.deliverFrame(at: 10 + frameDuration + 0.5, duration: frameDuration)

            sampler.deliverTick()

            #expect(sut.droppedFrames == 29)
        }

        @Test("The time between closing and reopening drops no frames")
        func noGapAcrossSessions() {
            let sampler = FakePerformanceSampler()
            let sut = PerformanceMonitor(sampler: sampler, threadSampler: NoThreads())
            let frameDuration: TimeInterval = 1.0 / 60
            sut.addViewer()
            sampler.deliverFrame(at: 10, duration: frameDuration)
            sampler.deliverTick()
            sut.removeViewer()
            sut.addViewer()
            sampler.deliverFrame(at: 70, duration: frameDuration)

            sampler.deliverTick()

            #expect(sut.droppedFrames == 0)
        }
    }

    #if os(macOS)
        import SwiftUI
        import ViewInspector

        @MainActor
        @Suite("Performance sampling follows its views", .timeLimit(.minutes(1)))
        struct PerformanceViewSamplingTests {
            @Test("The plugin's view starts sampling when it appears and stops it when it goes")
            func pluginView() async {
                let sampler = FakePerformanceSampler()
                let monitor = PerformanceMonitor(sampler: sampler, threadSampler: NoThreads())
                let sut = PerformancePluginView(monitor: monitor)

                ViewHosting.host(view: sut)
                for await isMonitoring in monitor.$isMonitoring.values where isMonitoring {
                    break
                }
                let startsWhileShown = sampler.starts
                ViewHosting.expel()
                for await isMonitoring in monitor.$isMonitoring.values where !isMonitoring {
                    break
                }

                #expect(startsWhileShown == 1)
                #expect(sampler.stops == 1)
                #expect(!sampler.isRunning)
            }

            @Test("The HUD readout starts sampling when it appears and stops it when it goes")
            func hud() async {
                let sampler = FakePerformanceSampler()
                let monitor = PerformanceMonitor(sampler: sampler, threadSampler: NoThreads())
                let sut = PerformanceHUD(monitor: monitor)

                ViewHosting.host(view: sut)
                for await isMonitoring in monitor.$isMonitoring.values where isMonitoring {
                    break
                }
                let startsWhileShown = sampler.starts
                ViewHosting.expel()
                for await isMonitoring in monitor.$isMonitoring.values where !isMonitoring {
                    break
                }

                #expect(startsWhileShown == 1)
                #expect(sampler.stops == 1)
                #expect(!sampler.isRunning)
            }
        }
    #endif
#endif
