#if DEBUG && os(macOS)
    import DebugDrawer
    @testable import DebugDrawerSidecarKit
    import DebugDrawerTweaks
    import Foundation
    import Testing
    import ViewInspector

    // The Tweaks plugin as a function of the capability's snapshot: each tweak drawn with the
    // control it declares, and the command each control sends.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct SidecarTweaksTests {
        private let tips = TweaksModel.Entry(title: "Shows Tips", key: "tips", control: .toggle, defaultValue: .bool(true), value: .bool(true))
        private let backend = TweaksModel.Entry(
            title: "Backend", key: "backend",
            control: .picker([TweakOption(title: "Production", value: .string("prod")), TweakOption(title: "Staging", value: .string("staging"))]),
            defaultValue: .string("prod"), value: .string("staging")
        )
        private let greeting = TweaksModel.Entry(
            title: "Greeting", key: "greeting", control: .text, defaultValue: .string("Hi"), value: .string("Hi")
        )
        private let pageSize = TweaksModel.Entry(
            title: "Page Size", key: "pageSize", control: .stepper(range: 10 ... 50, step: 10), defaultValue: .int(20), value: .int(20)
        )

        @Test("A switch and a picker send their tweak's value; a changed tweak shows its default and Reset; Reset All resets all")
        func viewSendsValues() throws {
            let snapshot = TweaksModel.Snapshot(tweaks: [tips, backend, greeting, pageSize])
            var sent: [TweaksModel.Command] = []
            let sut = TweaksSidecarView(snapshot: snapshot) { sent.append($0) }

            try sut.inspect().find(viewWithAccessibilityIdentifier: "Tweak-tips").find(ViewType.Toggle.self).tap()
            try sut.inspect().find(viewWithAccessibilityIdentifier: "Tweak-backend").find(ViewType.Picker.self)
                .select(value: TweakStoredValue.string("prod"))
            try sut.inspect().find(viewWithAccessibilityIdentifier: "Tweak-backend").find(button: "Reset").tap()
            try sut.inspect().find(button: "Reset All").tap()

            let expected: [TweaksModel.Command] = [
                .setValue(key: "tips", value: .bool(false)), .setValue(key: "backend", value: .string("prod")), .reset(key: "backend"), .resetAll
            ]
            #expect(sent == expected)
            #expect(throws: Never.self) { try sut.inspect().find(viewWithAccessibilityIdentifier: "Tweak-backend").find(text: "Default prod") }
            #expect(throws: (any Error).self) { try sut.inspect().find(viewWithAccessibilityIdentifier: "Tweak-tips").find(button: "Reset") }
        }

        @Test("A stepper steps within the tweak's range and sends the whole number")
        func stepperSendsInteger() throws {
            var sent: [TweaksModel.Command] = []
            let sut = TweaksSidecarView(snapshot: TweaksModel.Snapshot(tweaks: [pageSize])) { sent.append($0) }

            try sut.inspect().find(viewWithAccessibilityIdentifier: "Tweak-pageSize").find(ViewType.Stepper.self).increment()

            #expect(sent == [.setValue(key: "pageSize", value: .int(30))])
        }

        @Test("A text tweak's Set holds back its own value; with every tweak at its default there is no Reset All")
        func textSetDisabledAtValue() throws {
            var sent: [TweaksModel.Command] = []
            let sut = TweaksSidecarView(snapshot: TweaksModel.Snapshot(tweaks: [greeting])) { sent.append($0) }

            let set = try sut.inspect().find(viewWithAccessibilityIdentifier: "Tweak-greeting").find(button: "Set")

            #expect(set.isDisabled())
            #expect(sent.isEmpty)
            #expect(throws: (any Error).self) { try sut.inspect().find(button: "Reset All") }
        }

        @Test("With no production-safe tweak the plugin says so")
        func noTweaks() throws {
            let sut = TweaksSidecarView(snapshot: TweaksModel.Snapshot(tweaks: [])) { _ in }

            #expect(throws: Never.self) { try sut.inspect().find(text: "The app marks no tweak production-safe.") }
        }

        @Test("The shipped Tweaks plugin is served under the capability's ID")
        func shippedPlugin() {
            let sut = DebugDrawerSidecarPlugin.tweaks

            #expect([sut.id, sut.title, sut.icon] == [TweaksModel.pluginID, "Tweaks", "slider.horizontal.3"])
        }
    }
#endif
