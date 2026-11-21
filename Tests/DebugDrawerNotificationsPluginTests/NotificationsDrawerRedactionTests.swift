// ViewInspector is linked on Apple platforms only, and the views are tested on the Mac.
#if os(macOS)
    @testable import DebugDrawer
    @testable import DebugDrawerNotificationsPlugin
    import DebugDrawerTestSupport
    import Foundation
    import SwiftUI
    import Testing
    import ViewInspector

    // Hosted, so the view reads the drawer it is shown in from SwiftUI's environment, as the
    // drawer's panel sets it (offline, ViewInspector can't put a reference there). The shared
    // drawer keeps its standard rules, whose "token" pattern masks the device token; the drawer of
    // the test's own masks nothing, then masks it again by a pattern of its own.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct NotificationsDrawerRedactionTests {
        @Test("In a drawer of its own, Notifications masks the device token by that drawer's rules as they change, not shared's")
        func ownDrawerRedaction() async throws {
            let suite = temporarySuiteName("NotificationsDrawerRedactionTests.ownDrawerRedaction")
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let drawer = DebugDrawer(defaults: defaults)
            let masksNothing = DebugDrawerRedaction.none
            let masksDeviceToken = DebugDrawerRedaction.none.adding(keys: ["device"])
            drawer.redaction = masksNothing
            let model = NotificationsModel(
                registration: .registered(deviceToken: Data([0xAB, 0xCD, 0x01])),
                client: FakeNotificationCenter(authorization: .authorized),
                changes: FakeNotificationChangeSource()
            )
            let sut = NotificationsPluginView(model: model)
            let expectedOwn: [String] = ["abcd01"]
            let expectedChanged: [String] = [DebugDrawerRedaction.mask]
            var shownOwn: [String] = []
            var shownChanged: [String] = []

            try await ViewHosting.host(sut.environment(\.showingDrawer, drawer)) {
                try await sut.inspection.inspect { view in
                    shownOwn = try view.find(DeviceTokenSection.self).findAll(RedactedText.self).map { try $0.actualView().redacted }
                }
                drawer.redaction = masksDeviceToken
                try await sut.inspection.inspect { view in
                    shownChanged = try view.find(DeviceTokenSection.self).findAll(RedactedText.self).map { try $0.actualView().redacted }
                }
            }

            #expect(shownOwn == expectedOwn)
            #expect(shownChanged == expectedChanged)
        }
    }
#endif
