#if DEBUG && os(macOS)
    import DebugDrawer
    import DebugDrawerAnalytics
    @testable import DebugDrawerSidecarKit
    import Foundation
    import Testing
    import ViewInspector

    // The Analytics plugin as a function of the capability's snapshot.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct SidecarAnalyticsEventsTests {
        private let recorded = Date(timeIntervalSince1970: 1_800_000_000)

        @Test("Each event shows its name and its properties, sorted by key, as the app redacted them; Clear sends clear")
        func eventsShowProperties() throws {
            let event = AnalyticsEventsMirror.Event(
                id: 1, timestamp: recorded, name: "checkout_started",
                properties: ["items": 3, "email": "[REDACTED]", "tags": ["a", "b"]], source: "Checkout"
            )
            var sent: [AnalyticsEventsMirror.Command] = []
            let sut = AnalyticsEventsSidecarView(snapshot: AnalyticsEventsMirror.Snapshot(sessionID: UUID(), events: [event])) { sent.append($0) }

            try sut.inspect().find(button: "Clear").tap()

            let row = try sut.inspect().find(viewWithAccessibilityIdentifier: "AnalyticsEvent-1")
            #expect(sent == [.clear])
            #expect(throws: Never.self) { try row.find(text: "checkout_started") }
            #expect(throws: Never.self) { try row.find(text: "email: \"[REDACTED]\"") }
            #expect(throws: Never.self) { try row.find(text: "items: 3") }
            #expect(throws: Never.self) { try row.find(text: "tags: [\"a\", \"b\"]") }
            #expect(throws: Never.self) { try row.find(text: "Checkout") }
        }

        @Test("With no event the plugin says why: no session, or none recorded yet")
        func emptyStates() throws {
            let noSession = AnalyticsEventsSidecarView(snapshot: AnalyticsEventsMirror.Snapshot(sessionID: nil, events: [])) { _ in }
            let noEvents = AnalyticsEventsSidecarView(snapshot: AnalyticsEventsMirror.Snapshot(sessionID: UUID(), events: [])) { _ in }

            #expect(throws: Never.self) { try noSession.inspect().find(text: "The app mirrors the events it records only while a session is open.") }
            #expect(throws: Never.self) { try noEvents.inspect().find(text: "Events the app records while the session is open show here.") }
            #expect(throws: (any Error).self) { try noEvents.inspect().find(button: "Clear") }
        }

        @Test("The shipped Analytics plugin is served under the capability's ID")
        func shippedPlugin() {
            let sut = DebugDrawerSidecarPlugin.analyticsEvents

            #expect([sut.id, sut.title, sut.icon] == [AnalyticsEventsMirror.pluginID, "Analytics", "chart.bar"])
        }
    }
#endif
