#if DEBUG
    import DebugDrawer
    import DebugDrawerTestSupport
    @testable import DebugDrawerTweaksPlugin
    import Foundation
    import Testing

    // What the plugin refuses as it is made: declarations it couldn't show. A plugin is made on the
    // main actor, as DebugDrawerPlugin is isolated there.
    @MainActor
    @Suite
    struct TweaksPluginValidationTests {
        @Test("Two tweaks sharing a key throw duplicateKey when the plugin is made")
        func duplicateKeys() {
            let sections = [
                TweakSection("One") { Tweak.toggle("A", key: "shared", default: false) },
                TweakSection("Two") { Tweak.text("B", key: "shared", default: "") }
            ]

            #expect(throws: TweaksPlugin.InvalidTweaks.duplicateKey) {
                _ = try TweaksPlugin(sections: sections)
            }
        }

        @Test("A stepper whose default is outside its range throws stepperDefaultOutOfRange")
        func stepperDefaultOutsideRange() {
            let sections = [TweakSection("Network") { Tweak.stepper("Timeout", key: "timeout", default: 0, in: 1 ... 10) }]

            #expect(throws: TweaksPlugin.InvalidTweaks.stepperDefaultOutOfRange) {
                _ = try TweaksPlugin(sections: sections)
            }
        }

        @Test("A stepper whose default is a bound of its range is taken")
        func stepperDefaultAtBound() throws {
            let sections = [TweakSection("Network") {
                Tweak.stepper("Timeout", key: "timeout", default: 1, in: 1 ... 10)
                Tweak.stepper("Retries", key: "retries", default: 10, in: 1 ... 10)
            }]

            let sut = try TweaksPlugin(sections: sections)

            #expect(sut.sections.count == 1)
        }

        @Test("A stepper whose step is 0 throws stepperStepNotPositive")
        func stepperStepZero() {
            let sections = [TweakSection("Network") { Tweak.stepper("Timeout", key: "timeout", default: 5, in: 1 ... 10, step: 0) }]

            #expect(throws: TweaksPlugin.InvalidTweaks.stepperStepNotPositive) {
                _ = try TweaksPlugin(sections: sections)
            }
        }

        @Test("A stepper whose step is negative throws stepperStepNotPositive")
        func stepperStepNegative() {
            let sections = [TweakSection("Network") { Tweak.stepper("Timeout", key: "timeout", default: 5, in: 1 ... 10, step: -1) }]

            #expect(throws: TweaksPlugin.InvalidTweaks.stepperStepNotPositive) {
                _ = try TweaksPlugin(sections: sections)
            }
        }

        @Test("A string picker whose default isn't one of its options throws pickerDefaultNotAnOption")
        func pickerDefaultNotAnOption() {
            let sections = [TweakSection("Region") { Tweak.picker("Region", key: "region", options: ["us", "eu"], default: "apac") }]

            #expect(throws: TweaksPlugin.InvalidTweaks.pickerDefaultNotAnOption) {
                _ = try TweaksPlugin(sections: sections)
            }
        }

        @Test("A string picker with no options throws pickerDefaultNotAnOption")
        func pickerNoOptions() {
            let sections = [TweakSection("Region") { Tweak.picker("Region", key: "region", options: [], default: "us") }]

            #expect(throws: TweaksPlugin.InvalidTweaks.pickerDefaultNotAnOption) {
                _ = try TweaksPlugin(sections: sections)
            }
        }

        @Test("installTweaks with a refused declaration throws and leaves the drawer without the plugin")
        func installRefuses() throws {
            let suite = temporarySuiteName("TweaksPluginValidationTests")
            defer { UserDefaults().removePersistentDomain(forName: suite) }
            let drawer = try DebugDrawer(defaults: #require(UserDefaults(suiteName: suite)))

            #expect(throws: TweaksPlugin.InvalidTweaks.duplicateKey) {
                try drawer.installTweaks {
                    TweakSection("One") {
                        Tweak.toggle("A", key: "shared", default: false)
                        Tweak.toggle("B", key: "shared", default: true)
                    }
                }
            }
            #expect(!drawer.globalPlugins.contains { $0.id == "TweaksPlugin" })
        }
    }
#endif
