#if DEBUG
    @testable import DebugDrawer
    @testable import DebugDrawerLaunchTimePlugin
    import Foundation
    import Testing

    @MainActor
    @Suite("Launch Time install and uninstall")
    struct LaunchTimeLifecycleTests {
        /// A clock the test moves by hand.
        private final class FakeClock: UptimeClock {
            var now: TimeInterval
            init(_ now: TimeInterval) { self.now = now }
            var uptime: TimeInterval { now }
        }

        /// A process that started at `uptime`.
        private struct FakeProcessStart: ProcessStartReader {
            let uptime: TimeInterval?
            func processStartUptime() -> TimeInterval? { uptime }
        }

        @Test("Unregistering the plugin before the first frame removes it and the run-loop observer waiting for the frame")
        func uninstallStopsWaiting() throws {
            let suite = "LaunchTimeLifecycleTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let drawer = DebugDrawer(defaults: defaults)
            let firstFrame = _FirstFrameObserver()
            let model = LaunchTimeModel(clock: FakeClock(10), processStart: FakeProcessStart(uptime: 9), firstFrameObserver: firstFrame)
            let sut = LaunchTimePlugin(model: model)
            drawer.registerGlobal(sut)
            let observer = try #require(firstFrame.runLoopObserver)

            drawer.unregisterGlobal(id: sut.id)

            #expect(!drawer.globalPlugins.contains { $0.id == sut.id })
            #expect(firstFrame.runLoopObserver == nil)
            #expect(!CFRunLoopObserverIsValid(observer))
            #expect(model.firstFrameUptime == nil)
        }

        @Test("Installing again waits for the first frame again; uninstalling twice is harmless")
        func reinstallWaitsAgain() throws {
            let suite = "LaunchTimeLifecycleTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let drawer = DebugDrawer(defaults: defaults)
            let firstFrame = _FirstFrameObserver()
            let model = LaunchTimeModel(clock: FakeClock(10), processStart: FakeProcessStart(uptime: 9), firstFrameObserver: firstFrame)
            let sut = LaunchTimePlugin(model: model)
            drawer.registerGlobal(sut)
            sut.uninstall(from: drawer)
            sut.uninstall(from: drawer)

            sut.install(in: drawer)
            let isObserving = firstFrame.runLoopObserver != nil
            drawer.unregisterGlobal(id: sut.id)

            #expect(isObserving)
            #expect(firstFrame.runLoopObserver == nil)
        }

        @Test("In two drawers the plugin waits for the first frame until the last one uninstalls it")
        func twoDrawers() throws {
            let suite = "LaunchTimeLifecycleTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let first = DebugDrawer(defaults: defaults)
            let second = DebugDrawer(defaults: defaults)
            let firstFrame = _FirstFrameObserver()
            let model = LaunchTimeModel(clock: FakeClock(10), processStart: FakeProcessStart(uptime: 9), firstFrameObserver: firstFrame)
            let sut = LaunchTimePlugin(model: model)
            first.registerGlobal(sut)
            second.registerGlobal(sut)

            first.unregisterGlobal(id: sut.id)
            let isObservingWithOneLeft = firstFrame.runLoopObserver != nil
            second.unregisterGlobal(id: sut.id)

            #expect(isObservingWithOneLeft)
            #expect(firstFrame.runLoopObserver == nil)
        }

        @Test("Uninstalling after the first frame keeps the times measured")
        func uninstallKeepsTimes() throws {
            let suite = "LaunchTimeLifecycleTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let drawer = DebugDrawer(defaults: defaults)
            let clock = FakeClock(10)
            let model = LaunchTimeModel(clock: clock, processStart: FakeProcessStart(uptime: 9))
            let sut = LaunchTimePlugin(model: model)
            drawer.registerGlobal(sut)
            clock.now = 10.5
            model.perform(LaunchTimeCommand(.recordFirstFrame))

            drawer.unregisterGlobal(id: sut.id)

            #expect(model.firstFrameUptime == 10.5)
        }
    }
#endif
