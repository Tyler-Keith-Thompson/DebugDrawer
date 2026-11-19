#if DEBUG
    @testable import DebugDrawer
    @testable import DebugDrawerAppInfoPlugin
    import Foundation
    import Testing

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct AppInfoPluginTests {
        @Test("Refreshing a model over the real sources gives a memory footprint and an uptime above zero")
        func appMetricsRefresh() throws {
            let model = AppInfoModel(bundle: _BundleInfoSource(), device: _DeviceInfoSource(), process: _ProcessMetricsSource())
            model.perform(AppInfoCommand(.refresh))
            #expect(model.snapshot.footprintMB > 0)
            #expect(try #require(model.snapshot.uptime) > 0)
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
