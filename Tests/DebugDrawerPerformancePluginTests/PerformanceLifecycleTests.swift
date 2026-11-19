#if DEBUG
    #if os(macOS)
        import AppKit
    #endif
    @testable import DebugDrawer
    @testable import DebugDrawerPerformancePlugin
    import Foundation
    import SwiftUI
    import Testing

    /// Stands in for the display link and the 1 s timer: records starts and stops.
    @MainActor
    private final class FakePerformanceSampler: PerformanceSampler {
        private(set) var starts = 0
        private(set) var stops = 0
        private(set) var isRunning = false

        func start(
            frame: @escaping @MainActor (TimeInterval, TimeInterval) -> Void,
            tick: @escaping @MainActor () -> Void
        ) {
            starts += 1
            isRunning = true
        }

        func stop() {
            stops += 1
            isRunning = false
        }
    }

    private struct NoThreads: ThreadSampler {
        func sample() -> [ThreadCPU] {
            []
        }
    }

    @MainActor
    @Suite("Performance sampling follows the drawer's lifecycle hooks")
    struct PerformanceLifecycleTests {
        @Test("Registering the plugin starts nothing; it samples from didBecomeVisible to didBecomeHidden")
        func visibleToHidden() throws {
            let suite = "PerformanceLifecycleTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let drawer = DebugDrawer(defaults: defaults)
            let sampler = FakePerformanceSampler()
            let model = PerformanceModel(sampler: sampler, threadSampler: NoThreads())
            let sut = PerformancePlugin(model: model)

            drawer.registerGlobal(sut)
            let runningOnceRegistered = sampler.isRunning
            drawer.pluginContentDidAppear(id: sut.id)
            let runningWhileShown = sampler.isRunning
            drawer.pluginContentDidDisappear(id: sut.id)

            #expect(!runningOnceRegistered)
            #expect(runningWhileShown)
            #expect(sampler.starts == 1)
            #expect(sampler.stops == 1)
            #expect(!sampler.isRunning)
            #expect(!model.snapshot.isMonitoring)
        }

        @Test("Two drawers showing the plugin start the sampler once, and it stops only when both hide it")
        func twoDrawers() throws {
            let firstSuite = "PerformanceLifecycleTests.\(UUID().uuidString)"
            let secondSuite = "PerformanceLifecycleTests.\(UUID().uuidString)"
            let firstDefaults = try #require(UserDefaults(suiteName: firstSuite))
            let secondDefaults = try #require(UserDefaults(suiteName: secondSuite))
            defer {
                firstDefaults.removePersistentDomain(forName: firstSuite)
                secondDefaults.removePersistentDomain(forName: secondSuite)
            }
            let first = DebugDrawer(defaults: firstDefaults)
            let second = DebugDrawer(defaults: secondDefaults)
            let sampler = FakePerformanceSampler()
            let sut = PerformancePlugin(model: PerformanceModel(sampler: sampler, threadSampler: NoThreads()))
            first.registerGlobal(sut)
            second.registerGlobal(sut)

            first.pluginContentDidAppear(id: sut.id)
            second.pluginContentDidAppear(id: sut.id)
            first.pluginContentDidDisappear(id: sut.id)
            let runningWhileTheSecondShowsIt = sampler.isRunning
            second.pluginContentDidDisappear(id: sut.id)

            #expect(runningWhileTheSecondShowsIt)
            #expect(sampler.starts == 1)
            #expect(sampler.stops == 1)
            #expect(!sampler.isRunning)
        }

        @Test("Unregistering the plugin while it is shown stops the sampler")
        func removedWhileShown() throws {
            let suite = "PerformanceLifecycleTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let drawer = DebugDrawer(defaults: defaults)
            let sampler = FakePerformanceSampler()
            let sut = PerformancePlugin(model: PerformanceModel(sampler: sampler, threadSampler: NoThreads()))
            drawer.registerGlobal(sut)
            drawer.pluginContentDidAppear(id: sut.id)

            drawer.unregisterGlobal(id: sut.id)

            #expect(sampler.stops == 1)
            #expect(!sampler.isRunning)
        }

        @Test("Once the plugin is hidden, the production sampler's timer is cancelled and its display link invalidated")
        func productionSamplerStops() throws {
            let suite = "PerformanceLifecycleTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let drawer = DebugDrawer(defaults: defaults)
            let sampler = DisplayLinkSampler()
            let sut = PerformancePlugin(model: PerformanceModel(sampler: sampler, threadSampler: NoThreads()))
            drawer.registerGlobal(sut)

            drawer.pluginContentDidAppear(id: sut.id)
            let timerWhileShown = sampler.timer
            let displayLinkWhileShown = sampler.displayLink
            drawer.pluginContentDidDisappear(id: sut.id)

            #expect(timerWhileShown != nil)
            #expect(displayLinkWhileShown != nil)
            #expect(sampler.timer == nil)
            #expect(sampler.displayLink == nil)
        }

        #if os(macOS)
            @Test("The plugin's section body on screen in a drawer samples, and collapsing the section stops it")
            func hostedSection() throws {
                let suite = "PerformanceLifecycleTests.\(UUID().uuidString)"
                let defaults = try #require(UserDefaults(suiteName: suite))
                defer { defaults.removePersistentDomain(forName: suite) }
                let drawer = DebugDrawer(defaults: defaults)
                let sampler = FakePerformanceSampler()
                drawer.registerGlobal(PerformancePlugin(model: PerformanceModel(sampler: sampler, threadSampler: NoThreads())))
                let plugin = try #require(drawer.globalPlugins.first)
                let model = PerformanceSectionModel()
                let window = NSWindow(
                    contentRect: CGRect(x: -30000, y: -30000, width: 400, height: 800),
                    styleMask: .borderless, backing: .buffered, defer: false
                )
                window.isReleasedWhenClosed = false
                let host = NSHostingView(rootView: PerformanceSectionScreen(model: model, plugin: plugin, drawer: drawer))
                window.contentView = host
                window.orderFront(nil)
                defer { window.close() }

                host.layoutSubtreeIfNeeded()
                let runningWhileExpanded = sampler.isRunning
                model.isExpanded = false
                host.layoutSubtreeIfNeeded()

                #expect(runningWhileExpanded)
                #expect(sampler.starts == 1)
                #expect(sampler.stops == 1)
                #expect(!sampler.isRunning)
            }

            @Test("The plugin's view and HUD readout shown outside a drawer sample nothing")
            func outsideADrawer() {
                let sampler = FakePerformanceSampler()
                let model = PerformanceModel(sampler: sampler, threadSampler: NoThreads())
                let window = NSWindow(
                    contentRect: CGRect(x: -30000, y: -30000, width: 400, height: 800),
                    styleMask: .borderless, backing: .buffered, defer: false
                )
                window.isReleasedWhenClosed = false
                let host = NSHostingView(rootView: VStack {
                    PerformancePluginView(transport: .direct(to: model))
                    PerformanceHUD(transport: .direct(to: model))
                })
                window.contentView = host
                window.orderFront(nil)
                defer { window.close() }

                host.layoutSubtreeIfNeeded()

                #expect(sampler.starts == 0)
                #expect(!model.snapshot.isMonitoring)
            }
        #endif
    }

    #if os(macOS)
        /// Whether ``PerformanceSectionScreen``'s section is expanded.
        @MainActor
        private final class PerformanceSectionModel: ObservableObject {
            @Published var isExpanded = true
        }

        /// The plugin's section, as a drawer's outline shows it.
        private struct PerformanceSectionScreen: View {
            @ObservedObject var model: PerformanceSectionModel
            let plugin: AnyDebugDrawerPlugin
            let drawer: DebugDrawer

            var body: some View {
                DrawerPluginSection(plugin: plugin, isExpanded: model.isExpanded) {
                    Text(plugin.title)
                }
                .environment(\.showingDrawer, drawer)
            }
        }
    #endif
#endif
