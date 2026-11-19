#if DEBUG
    @testable import DebugDrawer
    @testable import DebugDrawerAppInfoPlugin
    import Foundation
    import Testing

    /// Stands in for the network path monitor: records starts and stops, and reports a status
    /// when the test says.
    @MainActor
    private final class FakeNetworkPathWatcher: NetworkPathWatcher {
        private(set) var starts = 0
        private(set) var stops = 0
        private var update: (@Sendable (String) -> Void)?

        var isWatching: Bool {
            update != nil
        }

        func start(_ update: @escaping @Sendable (String) -> Void) {
            starts += 1
            self.update = update
        }

        func stop() {
            stops += 1
            update = nil
        }
    }

    @MainActor
    @Suite("App Info stops watching the network once removed from every drawer")
    struct AppInfoUninstallTests {
        private static func drawer() throws -> (DebugDrawer, () -> Void) {
            let suite = "AppInfoUninstallTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            return (DebugDrawer(defaults: defaults), { defaults.removePersistentDomain(forName: suite) })
        }

        private static func plugin(watcher: FakeNetworkPathWatcher) -> AppInfoPlugin {
            AppInfoPlugin(
                buildMetadata: AppInfoBuildMetadata(),
                signing: AppSigningStore(source: FakeSigningInformation()),
                metrics: AppMetrics(processStart: nil, now: Date.init, timer: RunLoopSamplingTimer(interval: 2), pathWatcher: watcher)
            )
        }

        @Test("Unregistering removes the plugin from the drawer and stops the network watcher it started")
        func disappearsFromTheDrawer() throws {
            let (drawer, cleanUp) = try Self.drawer()
            defer { cleanUp() }
            let watcher = FakeNetworkPathWatcher()
            let sut = Self.plugin(watcher: watcher)
            drawer.registerGlobal(sut)
            let watchingOnceRegistered = watcher.isWatching

            drawer.unregisterGlobal(id: sut.id)

            #expect(watchingOnceRegistered)
            #expect(!drawer.globalPlugins.contains { $0.id == sut.id })
            #expect(watcher.stops == 1)
            #expect(!watcher.isWatching)
        }

        @Test("Uninstalling twice stops once, and registering again starts a new watcher")
        func uninstallTwiceThenReinstall() throws {
            let (drawer, cleanUp) = try Self.drawer()
            defer { cleanUp() }
            let watcher = FakeNetworkPathWatcher()
            let sut = Self.plugin(watcher: watcher)
            drawer.registerGlobal(sut)
            drawer.unregisterGlobal(id: sut.id)

            sut.uninstall(from: drawer)
            drawer.registerGlobal(sut)

            #expect(watcher.stops == 1)
            #expect(watcher.starts == 2)
            #expect(watcher.isWatching)
        }

        @Test("Two drawers holding the plugin watch once, until the second removes it")
        func twoDrawers() throws {
            let (first, cleanUpFirst) = try Self.drawer()
            let (second, cleanUpSecond) = try Self.drawer()
            defer {
                cleanUpFirst()
                cleanUpSecond()
            }
            let watcher = FakeNetworkPathWatcher()
            let sut = Self.plugin(watcher: watcher)
            first.registerGlobal(sut)
            second.registerGlobal(sut)

            first.unregisterGlobal(id: sut.id)
            let watchingWhileTheSecondHoldsIt = watcher.isWatching
            second.unregisterGlobal(id: sut.id)

            #expect(watchingWhileTheSecondHoldsIt)
            #expect(watcher.starts == 1)
            #expect(watcher.stops == 1)
        }

        @Test("Removing the plugin while shown stops the refresh timer too")
        func removedWhileShown() throws {
            let (drawer, cleanUp) = try Self.drawer()
            defer { cleanUp() }
            let timer = RunLoopSamplingTimer(interval: 2)
            let sut = AppInfoPlugin(
                buildMetadata: AppInfoBuildMetadata(),
                signing: AppSigningStore(source: FakeSigningInformation()),
                metrics: AppMetrics(processStart: nil, now: Date.init, timer: timer, pathWatcher: FakeNetworkPathWatcher())
            )
            drawer.registerGlobal(sut)
            drawer.pluginContentDidAppear(id: sut.id)

            drawer.unregisterGlobal(id: sut.id)

            #expect(timer.cancellable == nil)
        }

        @Test("The production watcher cancels its monitor on stop and makes a new one on the next start")
        func productionWatcherRestarts() {
            let sut = NWPathNetworkWatcher()

            sut.start { _ in }
            let first = sut.monitor
            sut.stop()
            let afterStop = sut.monitor
            sut.start { _ in }
            let second = sut.monitor
            sut.stop()

            #expect(first != nil)
            #expect(afterStop == nil)
            #expect(second != nil)
            #expect(first !== second)
        }
    }
#endif
