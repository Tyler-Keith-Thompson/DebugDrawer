#if DEBUG
    @testable import DebugDrawer
    @testable import DebugDrawerPerformancePlugin
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
        func installStartsNothing() {
            let sut = DebugDrawer.shared

            sut.installPerformance()

            #expect(!PerformanceMonitor.shared.isMonitoring)
        }
    }
#endif
