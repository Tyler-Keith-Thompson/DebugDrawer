// Exit tests start a child process, which only the Mac's test runs can do.
#if os(macOS) && DEBUG
    @testable import DebugDrawerTweaksPlugin
    import Testing

    @Suite
    struct TweaksPluginTrapExitTests {
        @Test("Two tweaks sharing a key trap when the plugin is made")
        func duplicateKeys() async {
            await #expect(processExitsWith: .failure) {
                // A plugin is made on the main actor, as DebugDrawerPlugin is isolated there.
                await MainActor.run {
                    _ = TweaksPlugin(sections: [
                        TweakSection("One") { Tweak.toggle("A", key: "shared", default: false) },
                        TweakSection("Two") { Tweak.text("B", key: "shared", default: "") }
                    ])
                }
            }
        }
    }
#endif
