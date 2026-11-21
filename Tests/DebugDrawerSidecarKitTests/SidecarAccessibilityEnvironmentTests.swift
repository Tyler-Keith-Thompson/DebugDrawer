#if DEBUG && os(macOS)
    import DebugDrawer
    import DebugDrawerAccessibility
    @testable import DebugDrawerSidecarKit
    import Foundation
    import Testing
    import ViewInspector

    // The Accessibility plugin as a function of the capability's snapshot: each setting the
    // system's or an override, and the command each picker sends.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct SidecarAccessibilityEnvironmentTests {
        @Test("Each picker sends its setting's override, System sends nil, and Reset resets every one")
        func pickersSendOverrides() throws {
            let snapshot = AccessibilityEnvironmentOverrides.Snapshot(dynamicTypeSize: .xLarge, increaseContrast: true)
            var sent: [AccessibilityEnvironmentOverrides.Command] = []
            let sut = AccessibilityEnvironmentView(snapshot: snapshot) { sent.append($0) }

            try sut.inspect().find(viewWithAccessibilityIdentifier: "Accessibility-DynamicType").find(ViewType.Picker.self)
                .select(value: AccessibilityEnvironmentOverrides.DynamicTypeSize?.some(.accessibility3))
            try sut.inspect().find(viewWithAccessibilityIdentifier: "Accessibility-IncreaseContrast").find(ViewType.Picker.self)
                .select(value: Bool?.none)
            try sut.inspect().find(viewWithAccessibilityIdentifier: "Accessibility-ReduceMotion").find(ViewType.Picker.self)
                .select(value: Bool?.some(true))
            try sut.inspect().find(button: "Reset").tap()

            #expect(sent == [.setDynamicTypeSize(.accessibility3), .setIncreaseContrast(nil), .setReduceMotion(true), .reset])
            #expect(throws: Never.self) { try sut.inspect().find(text: "Extra Large") }
        }

        @Test("With every setting the system's there is no Reset")
        func noResetAtSystemValues() throws {
            let sut = AccessibilityEnvironmentView(snapshot: AccessibilityEnvironmentOverrides.Snapshot()) { _ in }

            #expect(throws: (any Error).self) { try sut.inspect().find(button: "Reset") }
        }

        @Test("The shipped Accessibility plugin is served under the capability's ID")
        func shippedPlugin() {
            let sut = DebugDrawerSidecarPlugin.accessibilityEnvironmentOverrides

            #expect([sut.id, sut.title, sut.icon] == [AccessibilityEnvironmentOverrides.pluginID, "Accessibility", "accessibility"])
        }
    }
#endif
