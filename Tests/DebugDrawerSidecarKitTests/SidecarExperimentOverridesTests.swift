#if DEBUG && os(macOS)
    import DebugDrawer
    @testable import DebugDrawerReceiver
    @testable import DebugDrawerSidecarKit
    import Foundation
    import Testing
    import ViewInspector

    // The Experiments plugin as a function of the capability's snapshot: what each experiment
    // shows, and the command each control sends.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct SidecarExperimentOverridesTests {
        private let checkout = DebugDrawerExperiment(key: "checkout-flow", variants: ["control", "one-page"], assignedVariant: "control")
        private let onboarding = DebugDrawerExperiment(key: "onboarding", variants: ["short", "long"], assignedVariant: nil)

        @Test("Picking a variant forces it; a forced experiment is marked and Clear clears it; Clear All Overrides clears all")
        func viewSendsOverrides() throws {
            let snapshot = DebugDrawerExperimentOverrides.Snapshot(experiments: [checkout, onboarding], overriddenKeys: ["checkout-flow"])
            var sent: [DebugDrawerExperimentOverrides.Command] = []
            let sut = ExperimentOverridesView(snapshot: snapshot) { sent.append($0) }

            try sut.inspect().find(viewWithAccessibilityIdentifier: "Experiment-checkout-flow").find(ViewType.Picker.self).select(value: "one-page")
            try sut.inspect().find(viewWithAccessibilityIdentifier: "Experiment-checkout-flow").find(button: "Clear").tap()
            try sut.inspect().find(button: "Clear All Overrides").tap()

            let expected: [DebugDrawerExperimentOverrides.Command] = [
                .setOverride(experiment: "checkout-flow", variant: "one-page"), .clearOverride(experiment: "checkout-flow"), .clearAllOverrides
            ]
            #expect(sent == expected)
            #expect(throws: Never.self) { try sut.inspect().find(viewWithAccessibilityIdentifier: "Experiment-checkout-flow").find(text: "Forced") }
            #expect(throws: Never.self) { try sut.inspect().find(text: "Forced, so excluded from analytics: checkout-flow") }
        }

        @Test("An experiment the app hasn't bucketed reads Not enrolled, which sends nothing, and has no Clear")
        func notEnrolled() throws {
            let snapshot = DebugDrawerExperimentOverrides.Snapshot(experiments: [onboarding], overriddenKeys: [])
            var sent: [DebugDrawerExperimentOverrides.Command] = []
            let sut = ExperimentOverridesView(snapshot: snapshot) { sent.append($0) }

            let row = try sut.inspect().find(viewWithAccessibilityIdentifier: "Experiment-onboarding")
            try row.find(ViewType.Picker.self).select(value: "")

            #expect(sent.isEmpty)
            #expect(throws: Never.self) { try row.find(text: "Not enrolled") }
            #expect(throws: (any Error).self) { try row.find(button: "Clear") }
            #expect(throws: (any Error).self) { try sut.inspect().find(button: "Clear All Overrides") }
            #expect(throws: Never.self) { try sut.inspect().find(text: "No experiment forced.") }
        }

        @Test("With no experiment listed the plugin says so")
        func noExperiments() throws {
            let sut = ExperimentOverridesView(snapshot: DebugDrawerExperimentOverrides.Snapshot(experiments: [], overriddenKeys: [])) { _ in }

            #expect(throws: Never.self) { try sut.inspect().find(text: "The app's adapter lists no experiment a sidecar may force.") }
        }

        @Test("The shipped Experiments plugin is served under the capability's ID")
        func shippedPlugin() {
            let sut = DebugDrawerSidecarPlugin.experimentOverrides

            #expect([sut.id, sut.title, sut.icon] == [DebugDrawerExperimentOverrides.pluginID, "Experiments", "flask"])
        }
    }
#endif
