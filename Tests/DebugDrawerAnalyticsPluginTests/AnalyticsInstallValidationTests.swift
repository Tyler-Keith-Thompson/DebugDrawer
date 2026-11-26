#if DEBUG
    import DebugDrawer
    import DebugDrawerAnalyticsPlugin
    import Testing

    // In-process: a capacity below one is refused before the installer touches the shared drawer
    // or the event log, so nothing here changes the process.
    @MainActor
    @Suite
    struct AnalyticsInstallValidationTests {
        @Test("A capacity of 0 throws InvalidCapacity and installs nothing")
        func zeroCapacity() {
            let capacity = 0

            #expect(throws: AnalyticsEvents.InvalidCapacity.self) {
                try AnalyticsEvents.install(capacity: capacity)
            }
            #expect(!DebugDrawer.shared.globalPlugins.contains { $0.title == "Analytics" })
        }

        @Test("A negative capacity throws InvalidCapacity and installs nothing")
        func negativeCapacity() {
            let capacity = -1

            #expect(throws: AnalyticsEvents.InvalidCapacity.self) {
                try AnalyticsEvents.install(capacity: capacity)
            }
            #expect(!DebugDrawer.shared.globalPlugins.contains { $0.title == "Analytics" })
        }
    }
#endif
