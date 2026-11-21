#if DEBUG && os(macOS)
    import DebugDrawer
    @testable import DebugDrawerReceiver
    @testable import DebugDrawerSidecarKit
    import Foundation
    import Testing
    import ViewInspector

    // The Log Levels plugin as a function of the capability's snapshot: what each subsystem shows,
    // and the command each control sends.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct SidecarLogLevelsTests {
        private let checkout = DebugDrawerLogSubsystem(name: "com.example.checkout", levels: ["notice", "info", "debug"], level: "debug")
        private let sync = DebugDrawerLogSubsystem(name: "com.example.sync", levels: ["notice", "info", "debug"], level: "notice")

        @Test("Picking a level raises the subsystem; a raised one is marked and Reset resets it; Reset All Levels resets all")
        func viewSendsLevels() throws {
            let snapshot = DebugDrawerLogLevels.Snapshot(subsystems: [checkout, sync], raisedSubsystems: ["com.example.checkout"])
            var sent: [DebugDrawerLogLevels.Command] = []
            let sut = LogLevelsView(snapshot: snapshot) { sent.append($0) }

            try sut.inspect().find(viewWithAccessibilityIdentifier: "LogSubsystem-com.example.sync").find(ViewType.Picker.self).select(value: "info")
            try sut.inspect().find(viewWithAccessibilityIdentifier: "LogSubsystem-com.example.checkout").find(button: "Reset").tap()
            try sut.inspect().find(button: "Reset All Levels").tap()

            #expect(sent == [.setLevel(subsystem: "com.example.sync", level: "info"), .reset(subsystem: "com.example.checkout"), .resetAll])
            #expect(throws: Never.self) {
                try sut.inspect().find(viewWithAccessibilityIdentifier: "LogSubsystem-com.example.checkout").find(text: "Raised")
            }
            #expect(throws: (any Error).self) {
                try sut.inspect().find(viewWithAccessibilityIdentifier: "LogSubsystem-com.example.sync").find(button: "Reset")
            }
            #expect(throws: Never.self) { try sut.inspect().find(text: "Raised until the session ends: com.example.checkout") }
        }

        @Test("With nothing raised there is no Reset All Levels; with no subsystem listed the plugin says so")
        func nothingRaisedAndNothingListed() throws {
            let idle = LogLevelsView(snapshot: DebugDrawerLogLevels.Snapshot(subsystems: [sync], raisedSubsystems: [])) { _ in }
            let empty = LogLevelsView(snapshot: DebugDrawerLogLevels.Snapshot(subsystems: [], raisedSubsystems: [])) { _ in }

            #expect(throws: (any Error).self) { try idle.inspect().find(button: "Reset All Levels") }
            #expect(throws: Never.self) { try idle.inspect().find(text: "No subsystem raised.") }
            #expect(throws: Never.self) { try empty.inspect().find(text: "The app's adapter lists no subsystem a sidecar may raise.") }
        }

        @Test("The shipped Log Levels plugin is served under the capability's ID")
        func shippedPlugin() {
            let sut = DebugDrawerSidecarPlugin.logLevels

            #expect([sut.id, sut.title, sut.icon] == [DebugDrawerLogLevels.pluginID, "Log Levels", "text.alignleft"])
        }
    }
#endif
