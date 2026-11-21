#if DEBUG
    @testable import DebugDrawer
    @testable import DebugDrawerPerformancePlugin
    import DebugDrawerTestSupport
    import Foundation
    import Testing

    @MainActor
    @Suite("Performance plugin")
    struct PerformancePluginTests {
        @Test("The plugin is titled Performance and has an identifier")
        func conformance() {
            let expectedTitle = "Performance"

            let sut = PerformancePlugin()

            #expect(sut.title == expectedTitle)
            #expect(!sut.id.isEmpty)
        }

        @Test("Installing the plugin samples nothing until its view or HUD shows")
        func installStartsNothing() throws {
            let suite = temporarySuiteName("PerformancePluginTests")
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let sut = DebugDrawer(defaults: defaults)

            sut.installPerformance()

            #expect(!PerformanceModel.shared.snapshot.isMonitoring)
        }
    }
#endif
