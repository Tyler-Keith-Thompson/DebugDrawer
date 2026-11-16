// ViewInspector is linked on Apple platforms only, and the views are tested on the Mac.
#if os(macOS)
    @testable import DebugDrawerTweaksPlugin
    import SwiftUI
    import Testing
    import ViewInspector

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct TweaksViewTests {
        @Test("Flipping a toggle stores its new value")
        func toggleStores() throws {
            let storage = FakeTweakStorage()
            let section = TweakSection("Features") {
                Tweak.toggle("New checkout", key: "newCheckout", default: false)
            }
            let sut = TweaksPluginView(sections: [section], store: TweakStore(storage: storage))

            try sut.inspect().find(ViewType.Toggle.self).tap()

            #expect(storage.values == ["newCheckout": .bool(true)])
        }

        @Test("Picking an option stores its raw value")
        func pickerStores() throws {
            let storage = FakeTweakStorage()
            let section = TweakSection("Server") {
                Tweak.picker("Server", key: "server", default: Server.production)
            }
            let sut = TweaksPluginView(sections: [section], store: TweakStore(storage: storage))

            try sut.inspect().find(ViewType.Picker.self).select(value: TweakStoredValue.string("staging"))

            #expect(storage.values == ["server": .string("staging")])
        }

        @Test("Typing in a text tweak stores the text, empty text included")
        func textStores() throws {
            let storage = FakeTweakStorage()
            let section = TweakSection("Copy") {
                Tweak.text("Greeting", key: "greeting", default: "Hello")
            }
            let sut = TweaksPluginView(sections: [section], store: TweakStore(storage: storage))

            try sut.inspect().find(ViewType.TextField.self).setInput("")

            #expect(storage.values == ["greeting": .string("")])
        }

        @Test("Stepping stores the next value along the step")
        func stepperStores() throws {
            let storage = FakeTweakStorage()
            let section = TweakSection("Server") {
                Tweak.stepper("Timeout", key: "timeout", default: 30, in: 5 ... 120, step: 5)
            }
            let sut = TweaksPluginView(sections: [section], store: TweakStore(storage: storage))

            try sut.inspect().find(ViewType.Stepper.self).increment()

            #expect(storage.values == ["timeout": .int(35)])
        }

        @Test("An action's button runs its closure and stores nothing")
        func actionRuns() throws {
            let storage = FakeTweakStorage()
            let counter = PressCounter()
            let section = TweakSection("Session") {
                TweakAction("Expire token") { counter.presses += 1 }
            }
            let sut = TweaksPluginView(sections: [section], store: TweakStore(storage: storage))

            try sut.inspect().find(button: "Expire token").tap()

            #expect(counter.presses == 1)
            #expect(storage.values.isEmpty)
        }

        @Test("A changed tweak has a reset button, which removes its stored value")
        func resetOne() throws {
            let storage = FakeTweakStorage(["timeout": .int(60), "server": .string("staging")])
            let section = TweakSection("Server") {
                Tweak.stepper("Timeout", key: "timeout", default: 30, in: 5 ... 120)
                Tweak.picker("Server", key: "server", default: Server.production)
            }
            let sut = TweaksPluginView(sections: [section], store: TweakStore(storage: storage))

            try sut.inspect().find(ViewType.Button.self, where: { try $0.accessibilityLabel().string() == "Reset Timeout" }).tap()

            #expect(storage.values == ["server": .string("staging")])
        }

        @Test("A tweak at its default has no reset button")
        func noResetAtDefault() throws {
            let storage = FakeTweakStorage(["timeout": .int(30)])
            let section = TweakSection("Server") {
                Tweak.stepper("Timeout", key: "timeout", default: 30, in: 5 ... 120)
            }
            let sut = TweaksPluginView(sections: [section], store: TweakStore(storage: storage))

            let resetButtons = try sut.inspect().findAll(ViewType.Button.self, where: { try $0.accessibilityLabel().string() == "Reset Timeout" })

            #expect(resetButtons.isEmpty)
        }

        @Test("Reset All removes every declared tweak's value and leaves other keys alone")
        func resetAll() throws {
            let storage = FakeTweakStorage(["newCheckout": .bool(true), "timeout": .int(60), "unrelated": .int(1)])
            let features = TweakSection("Features") {
                Tweak.toggle("New checkout", key: "newCheckout", default: false)
            }
            let server = TweakSection("Server") {
                Tweak.stepper("Timeout", key: "timeout", default: 30, in: 5 ... 120)
            }
            let sut = TweaksPluginView(sections: [features, server], store: TweakStore(storage: storage))

            try sut.inspect().find(button: "Reset All").tap()

            #expect(storage.values == ["unrelated": .int(1)])
        }

        @Test("Reset All is disabled while every tweak reads its default")
        func resetAllDisabled() throws {
            let section = TweakSection("Features") {
                Tweak.toggle("New checkout", key: "newCheckout", default: false)
            }
            let sut = TweaksPluginView(sections: [section], store: TweakStore(storage: FakeTweakStorage()))

            let actual = try sut.inspect().find(button: "Reset All").isDisabled()

            #expect(actual)
        }

        @Test("A stored value that is no longer an option shows the default, with no reset button")
        func unknownOptionShowsDefault() throws {
            let storage = FakeTweakStorage(["server": .string("qa")])
            let section = TweakSection("Server") {
                Tweak.picker("Server", key: "server", default: Server.production)
            }
            let expected = TweakStoredValue.string("production")

            let actual = TweakSectionState(section, stored: storage.value(forKey:))

            let row = try #require(actual.rows.first)
            guard case let .picker(_, selection) = row.control else {
                Issue.record("The server tweak isn't a picker")
                return
            }
            #expect(selection == expected)
            #expect(!row.isModified)
        }

        @Test("Every control is labelled with its tweak's title")
        func labels() throws {
            let section = TweakSection("All") {
                Tweak.picker("Server", key: "server", default: Server.production)
                Tweak.text("Greeting", key: "greeting", default: "Hello")
            }
            let sut = TweaksPluginView(sections: [section], store: TweakStore(storage: FakeTweakStorage()))
            let inspected = try sut.inspect()

            #expect(try inspected.find(ViewType.Picker.self).accessibilityLabel().string() == "Server")
            #expect(try inspected.find(ViewType.TextField.self).accessibilityLabel().string() == "Greeting")
        }

        @Test("With no tweaks declared, the plugin says so")
        func empty() throws {
            let sut = TweaksPluginView(sections: [], store: TweakStore(storage: FakeTweakStorage()))

            let actual = try sut.inspect().find(text: "No tweaks declared")

            #expect(try actual.string() == "No tweaks declared")
        }
    }

    /// Counts an action's presses; main-actor isolated, so the action's closure can change it.
    @MainActor
    private final class PressCounter {
        var presses = 0
    }
#endif
