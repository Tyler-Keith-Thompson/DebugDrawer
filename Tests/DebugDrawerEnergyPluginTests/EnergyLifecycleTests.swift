#if DEBUG
    #if os(macOS)
        import AppKit
    #endif
    @testable import DebugDrawer
    @testable import DebugDrawerEnergyPlugin
    import Foundation
    import SwiftUI
    import Testing

    /// Stands in for the 1 s timer: records starts and stops.
    @MainActor
    private final class FakeSamplingTimer: SamplingTimer {
        private(set) var starts = 0
        private(set) var stops = 0
        private(set) var isRunning = false

        func start(_ tick: @escaping @MainActor () -> Void) {
            starts += 1
            isRunning = true
        }

        func stop() {
            stops += 1
            isRunning = false
        }
    }

    @MainActor
    @Suite("Energy sampling follows the drawer's lifecycle hooks")
    struct EnergyLifecycleTests {
        @Test("Registering the plugin starts nothing; it samples from didBecomeVisible to didBecomeHidden")
        func visibleToHidden() throws {
            let suite = "EnergyLifecycleTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let drawer = DebugDrawer(defaults: defaults)
            let timer = FakeSamplingTimer()
            let monitor = EnergyMonitor(batteryMonitoring: nil, timer: timer)
            let sut = EnergyPlugin(monitor: monitor)

            drawer.registerGlobal(sut)
            let runningOnceRegistered = timer.isRunning
            drawer.pluginContentDidAppear(id: sut.id)
            let runningWhileShown = timer.isRunning
            drawer.pluginContentDidDisappear(id: sut.id)

            #expect(!runningOnceRegistered)
            #expect(runningWhileShown)
            #expect(timer.starts == 1)
            #expect(timer.stops == 1)
            #expect(!timer.isRunning)
            #expect(!monitor.isMonitoring)
        }

        @Test("The app's start() keeps sampling after the drawer hides the plugin")
        func appDemandOutlivesHidden() throws {
            let suite = "EnergyLifecycleTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let drawer = DebugDrawer(defaults: defaults)
            let timer = FakeSamplingTimer()
            let monitor = EnergyMonitor(batteryMonitoring: nil, timer: timer)
            let sut = EnergyPlugin(monitor: monitor)
            drawer.registerGlobal(sut)
            monitor.start()

            drawer.pluginContentDidAppear(id: sut.id)
            drawer.pluginContentDidDisappear(id: sut.id)
            let runningAfterHidden = timer.isRunning
            monitor.stop()

            #expect(runningAfterHidden)
            #expect(timer.starts == 1)
            #expect(timer.stops == 1)
        }

        @Test("Once the plugin is hidden, the production timer is cancelled")
        func productionTimerStops() throws {
            let suite = "EnergyLifecycleTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let drawer = DebugDrawer(defaults: defaults)
            let timer = RunLoopSamplingTimer()
            let sut = EnergyPlugin(monitor: EnergyMonitor(batteryMonitoring: nil, timer: timer))
            drawer.registerGlobal(sut)

            drawer.pluginContentDidAppear(id: sut.id)
            let timerWhileShown = timer.cancellable
            drawer.pluginContentDidDisappear(id: sut.id)

            #expect(timerWhileShown != nil)
            #expect(timer.cancellable == nil)
        }

        #if os(macOS)
            @Test("The plugin's view shown outside a drawer samples nothing")
            func outsideADrawer() {
                let timer = FakeSamplingTimer()
                let monitor = EnergyMonitor(batteryMonitoring: nil, timer: timer)
                let window = NSWindow(
                    contentRect: CGRect(x: -30000, y: -30000, width: 400, height: 600),
                    styleMask: .borderless, backing: .buffered, defer: false
                )
                window.isReleasedWhenClosed = false
                let host = NSHostingView(rootView: EnergyPluginView(transport: .direct(to: monitor)))
                window.contentView = host
                window.orderFront(nil)
                defer { window.close() }

                host.layoutSubtreeIfNeeded()

                #expect(timer.starts == 0)
                #expect(!monitor.isMonitoring)
            }
        #endif
    }
#endif
