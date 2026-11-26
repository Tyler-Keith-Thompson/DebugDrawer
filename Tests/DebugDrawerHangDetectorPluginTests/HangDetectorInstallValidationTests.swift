#if DEBUG
    import DebugDrawer
    import DebugDrawerHangDetectorPlugin
    import Testing

    // In-process: a threshold that isn't positive is refused before the installer registers the
    // plugin or starts the watcher, so nothing here changes the process.
    @MainActor
    @Suite
    struct HangDetectorInstallValidationTests {
        @Test("A threshold of zero throws NonPositiveThreshold and installs nothing")
        func zeroThreshold() {
            let threshold: Duration = .zero

            #expect(throws: HangDetector.NonPositiveThreshold.self) {
                try HangDetector.install(threshold: threshold)
            }
            #expect(!DebugDrawer.shared.globalPlugins.contains { $0.title == "Hangs" })
        }

        @Test("A negative threshold throws NonPositiveThreshold and installs nothing")
        func negativeThreshold() {
            let threshold: Duration = .milliseconds(-1)

            #expect(throws: HangDetector.NonPositiveThreshold.self) {
                try HangDetector.install(threshold: threshold)
            }
            #expect(!DebugDrawer.shared.globalPlugins.contains { $0.title == "Hangs" })
        }
    }
#endif
