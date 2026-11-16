#if DEBUG
    import DebugDrawer
    @testable import DebugDrawerTweaksPlugin
    import Foundation
    import Testing

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct TweaksPluginTests {
        @Test("The plugin offers each action to the drawer's search, found by its section's title too")
        func actions() {
            let counter = ActionCounter()
            let sut = TweaksPlugin(sections: [
                TweakSection("Session") {
                    Tweak.toggle("Signed in", key: "signedIn", default: true)
                    TweakAction("Expire token") { counter.runs += 1 }
                },
                TweakSection("Onboarding") {
                    TweakAction("Reset onboarding") {}
                }
            ])

            let actual = sut.actions
            actual.first?.perform()

            #expect(actual.map(\.title) == ["Expire token", "Reset onboarding"])
            #expect(actual.map(\.keywords) == [["Session"], ["Onboarding"]])
            #expect(counter.runs == 1)
        }

        @Test("The plugin is Tweaks, in the App category")
        func identity() {
            let sut = TweaksPlugin(sections: [])

            #expect(sut.title == "Tweaks")
            #expect(sut.category == "App")
            #expect(sut.icon == "slider.horizontal.3")
        }

        @Test("Installing registers one Tweaks plugin, and installing again replaces it")
        func install() {
            let drawer = DebugDrawer.shared
            let storage = FakeTweakStorage()

            drawer.installTweaks(storage: storage) {
                TweakSection("First") {
                    Tweak.toggle("Install test", key: "tweaks.test.install", default: false)
                }
            }
            drawer.installTweaks(storage: storage) {
                TweakSection("Second") {
                    TweakAction("Install test action") {}
                }
            }

            let actual = drawer.globalPlugins.filter { $0.id == "TweaksPlugin" }
            #expect(actual.map(\.actions.count) == [1])
            #expect(actual.map(\.contributesToReport) == [true])
        }

        @Test("The report gets tweaks.json with each tweak's title, value and whether it is the default, a token masked")
        func report() throws {
            let sections = [
                TweakSection("Server") {
                    Tweak.picker("Server", key: "server", default: Server.production)
                    Tweak.text("Token", key: "apiToken", default: "")
                },
                TweakSection("Session") {
                    TweakAction("Expire token") {}
                }
            ]
            let stored: [String: TweakStoredValue] = ["server": .string("staging"), "apiToken": .string("t0k3n")]
            let expected = """
            {
              "apiToken" : {
                "isDefault" : false,
                "title" : "Token",
                "value" : "[REDACTED]"
              },
              "server" : {
                "isDefault" : false,
                "title" : "Server",
                "value" : "staging"
              }
            }
            """
            var actual = DebugDrawerReport()

            TweaksPlugin.contribute(sections, stored: { stored[$0] }, to: &actual, redaction: .standard)

            let file = try #require(actual.files.first)
            #expect(file.name == "tweaks.json")
            #expect(file.kind == .json)
            #expect(String(bytes: file.data, encoding: .utf8) == expected)
        }

        @Test("Sections with no tweaks add nothing to the report")
        func reportEmpty() {
            let sections = [TweakSection("Session") { TweakAction("Expire token") {} }]
            var actual = DebugDrawerReport()

            TweaksPlugin.contribute(sections, stored: { _ in nil }, to: &actual, redaction: .standard)

            #expect(actual.files.isEmpty)
        }
    }

    /// Counts an action's runs; main-actor isolated, so the action's closure can change it.
    @MainActor
    private final class ActionCounter {
        var runs = 0
    }
#endif
