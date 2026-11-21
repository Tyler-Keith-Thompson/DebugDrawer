// ViewInspector is linked on Apple platforms only, and the views are tested on the Mac.
#if os(macOS)
    @testable import DebugDrawer
    @testable import DebugDrawerKeychainPlugin
    import DebugDrawerTestSupport
    import Foundation
    import SwiftUI
    import Testing
    import ViewInspector

    // Hosted, so the view reads the drawer it is shown in from SwiftUI's environment, as the
    // drawer's panel sets it (offline, ViewInspector can't put a reference there). The shared
    // drawer keeps its standard rules, which mask the fixture's password for its "API token"
    // label; the drawer of the test's own masks nothing, then masks the account.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct KeychainDrawerRedactionTests {
        @Test("In a drawer of its own, Keychain masks the open item's password by that drawer's rules as they change, not shared's")
        func ownDrawerRedaction() async throws {
            let suite = temporarySuiteName("KeychainDrawerRedactionTests.ownDrawerRedaction")
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let drawer = DebugDrawer(defaults: defaults)
            let masksNothing = DebugDrawerRedaction.none
            let masksAccount = DebugDrawerRedaction.none.adding(keys: ["ada"])
            drawer.redaction = masksNothing
            let item = KeychainFixtures.password
            let sut = KeychainPluginView(
                transport: DebugDrawerPluginTransport(
                    initial: KeychainSnapshot(contents: .items([item]), selection: KeychainOpenItem(item: item, value: .held)),
                    snapshots: AsyncStream { $0.finish() },
                    send: { _ in }
                ),
                revealedValue: { _ in Data("s3cr3t".utf8) }
            )
            let expectedOwn: [String] = ["s3cr3t"]
            let expectedChanged: [String] = [DebugDrawerRedaction.mask]
            var shownOwn: [String] = []
            var rulesOwn: DebugDrawerRedaction?
            var shownChanged: [String] = []

            try await ViewHosting.host(sut.environment(\.showingDrawer, drawer)) {
                try await sut.inspection.inspect { view in
                    shownOwn = try view.find(KeychainItemDetail.self).findAll(RedactedText.self).map { try $0.actualView().redacted }
                    rulesOwn = try view.find(KeychainListView.self).actualView().redaction
                }
                drawer.redaction = masksAccount
                try await sut.inspection.inspect { view in
                    shownChanged = try view.find(KeychainItemDetail.self).findAll(RedactedText.self).map { try $0.actualView().redacted }
                }
            }

            #expect(shownOwn == expectedOwn)
            #expect(rulesOwn == masksNothing)
            #expect(shownChanged == expectedChanged)
        }
    }
#endif
