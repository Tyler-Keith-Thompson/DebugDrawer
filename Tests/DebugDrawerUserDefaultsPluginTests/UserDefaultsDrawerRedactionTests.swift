// ViewInspector is linked on Apple platforms only, and the views are tested on the Mac.
#if os(macOS)
    @testable import DebugDrawer
    import DebugDrawerTestSupport
    @testable import DebugDrawerUserDefaultsPlugin
    import Foundation
    import SwiftUI
    import Testing
    import ViewInspector

    // Hosted, so the view reads the drawer it is shown in from SwiftUI's environment, as the
    // drawer's panel sets it (offline, ViewInspector can't put a reference there). The shared
    // drawer keeps its standard rules, which mask "sessionID" and not "plan"; the drawer of the
    // test's own masks the other way round.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct UserDefaultsDrawerRedactionTests {
        @Test("In a drawer of its own, UserDefaults masks its rows' values by that drawer's rules as they change, not shared's")
        func ownDrawerRedaction() async throws {
            let suite = temporarySuiteName("UserDefaultsDrawerRedactionTests.ownDrawerRedaction")
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let drawer = DebugDrawer(defaults: defaults)
            let masksPlan = DebugDrawerRedaction.none.adding(keys: ["plan"])
            let masksNothing = DebugDrawerRedaction.none
            drawer.redaction = masksPlan
            let sut = UserDefaultsPluginView(transport: DebugDrawerPluginTransport(
                initial: UserDefaultsSnapshot(entries: [
                    DefaultsEntry(key: "plan", value: .string("premium")),
                    DefaultsEntry(key: "sessionID", value: .string("s3ss10n"))
                ]),
                snapshots: AsyncStream { $0.finish() },
                send: { _ in }
            ))
            let expectedOwn: [String: String] = ["plan": DebugDrawerRedaction.mask, "sessionID": "s3ss10n"]
            let expectedChanged: [String: String] = ["plan": "premium", "sessionID": "s3ss10n"]
            var shownOwn: [String: String] = [:]
            var shownChanged: [String: String] = [:]

            try await ViewHosting.host(sut.environment(\.showingDrawer, drawer)) {
                try await sut.inspection.inspect { view in
                    shownOwn = try Dictionary(uniqueKeysWithValues: view.findAll(DefaultsEntryRow.self).map {
                        let row = try $0.actualView()
                        return (row.entry.key, row.entry.copiedValue(redaction: row.redaction))
                    })
                }
                drawer.redaction = masksNothing
                try await sut.inspection.inspect { view in
                    shownChanged = try Dictionary(uniqueKeysWithValues: view.findAll(DefaultsEntryRow.self).map {
                        let row = try $0.actualView()
                        return (row.entry.key, row.entry.copiedValue(redaction: row.redaction))
                    })
                }
            }

            #expect(shownOwn == expectedOwn)
            #expect(shownChanged == expectedChanged)
        }
    }
#endif
