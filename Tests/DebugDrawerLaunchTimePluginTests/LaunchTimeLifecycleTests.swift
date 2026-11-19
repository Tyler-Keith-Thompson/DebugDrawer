#if DEBUG
    @testable import DebugDrawer
    @testable import DebugDrawerLaunchTimePlugin
    import Foundation
    import Testing

    @MainActor
    @Suite("Launch Time install and uninstall")
    struct LaunchTimeLifecycleTests {
        /// A clock the test moves by hand.
        private final class FakeClock {
            var now: TimeInterval
            init(_ now: TimeInterval) { self.now = now }
        }

        @Test("Unregistering the plugin before the first frame removes it and the run-loop observer waiting for the frame")
        func uninstallStopsWaiting() throws {
            let suite = "LaunchTimeLifecycleTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let drawer = DebugDrawer(defaults: defaults)
            let tracker = LaunchTimeTracker(clock: { 10 }, processStartUptime: 9)
            let sut = LaunchTimePlugin(tracker: tracker)
            drawer.registerGlobal(sut)
            let observer = try #require(tracker.firstFrameObserver)

            drawer.unregisterGlobal(id: sut.id)

            #expect(!drawer.globalPlugins.contains { $0.id == sut.id })
            #expect(tracker.firstFrameObserver == nil)
            #expect(!CFRunLoopObserverIsValid(observer))
            #expect(tracker.firstFrameUptime == nil)
        }

        @Test("Installing again waits for the first frame again; uninstalling twice is harmless")
        func reinstallWaitsAgain() throws {
            let suite = "LaunchTimeLifecycleTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let drawer = DebugDrawer(defaults: defaults)
            let tracker = LaunchTimeTracker(clock: { 10 }, processStartUptime: 9)
            let sut = LaunchTimePlugin(tracker: tracker)
            drawer.registerGlobal(sut)
            sut.uninstall(from: drawer)
            sut.uninstall(from: drawer)

            sut.install(in: drawer)
            let isObserving = tracker.firstFrameObserver != nil
            drawer.unregisterGlobal(id: sut.id)

            #expect(isObserving)
            #expect(tracker.firstFrameObserver == nil)
        }

        @Test("In two drawers the plugin waits for the first frame until the last one uninstalls it")
        func twoDrawers() throws {
            let suite = "LaunchTimeLifecycleTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let first = DebugDrawer(defaults: defaults)
            let second = DebugDrawer(defaults: defaults)
            let tracker = LaunchTimeTracker(clock: { 10 }, processStartUptime: 9)
            let sut = LaunchTimePlugin(tracker: tracker)
            first.registerGlobal(sut)
            second.registerGlobal(sut)

            first.unregisterGlobal(id: sut.id)
            let isObservingWithOneLeft = tracker.firstFrameObserver != nil
            second.unregisterGlobal(id: sut.id)

            #expect(isObservingWithOneLeft)
            #expect(tracker.firstFrameObserver == nil)
        }

        @Test("Uninstalling after the first frame keeps the times measured")
        func uninstallKeepsTimes() throws {
            let suite = "LaunchTimeLifecycleTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let drawer = DebugDrawer(defaults: defaults)
            let clock = FakeClock(10)
            let tracker = LaunchTimeTracker(clock: { clock.now }, processStartUptime: 9)
            let sut = LaunchTimePlugin(tracker: tracker)
            drawer.registerGlobal(sut)
            clock.now = 10.5
            tracker.recordFirstFrame()

            drawer.unregisterGlobal(id: sut.id)

            #expect(tracker.firstFrameUptime == 10.5)
        }
    }
#endif
