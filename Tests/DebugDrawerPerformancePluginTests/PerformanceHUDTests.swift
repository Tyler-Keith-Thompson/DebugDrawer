#if DEBUG
    @testable import DebugDrawer
    @testable import DebugDrawerPerformancePlugin
    import Testing

    @MainActor
    @Suite("Performance HUD")
    struct PerformanceHUDTests {
        @Test("Performance offers a HUD readout")
        func performanceOffersAHUD() {
            let sut = AnyDebugDrawerPlugin(PerformancePlugin())

            #expect(sut.hasHUD)
            #expect(sut.hud != nil)
        }
    }
#endif
