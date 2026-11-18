#if DEBUG
    @testable import DebugDrawer
    @testable import DebugDrawerAppInfoPlugin
    import Foundation
    import Testing

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct AppInfoPluginTests {
        @Test("Refreshing the shared metrics gives a memory footprint and an uptime above zero")
        func appMetricsRefresh() throws {
            let metrics = AppMetrics.shared
            metrics.refresh()
            #expect(metrics.footprintMB > 0)
            #expect(try #require(metrics.uptime) > 0)
        }

        @Test("The plugin is titled App Info, with the info.circle icon")
        func pluginConformance() {
            let plugin = AppInfoPlugin()
            #expect(plugin.title == "App Info")
            #expect(plugin.icon == "info.circle")
        }

        @Test("The machine's hardware name is not empty")
        func machineHardwareName() {
            let name = ProcessInfo.processInfo.machineHardwareName
            #expect(!name.isEmpty)
        }
    }
#endif
