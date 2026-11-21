// ViewInspector is linked on Apple platforms only, and the views are tested on the Mac.
#if os(macOS)
    @testable import DebugDrawer
    @testable import DebugDrawerNetworkPlugin
    import DebugDrawerTestSupport
    import Foundation
    import SwiftUI
    import Testing
    import ViewInspector

    // Hosted, so the view reads the drawer it is shown in from SwiftUI's environment, as the
    // drawer's panel sets it (offline, ViewInspector can't put a reference there). The shared
    // drawer keeps its standard rules, which mask Authorization and not X-Own-Secret; the drawer
    // of the test's own masks the other way round.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct NetworkDrawerRedactionTests {
        @Test("In a drawer of its own, Network masks its rows and its export by that drawer's rules as they change, not shared's")
        func ownDrawerRedaction() async throws {
            let suite = temporarySuiteName("NetworkDrawerRedactionTests.ownDrawerRedaction")
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let drawer = DebugDrawer(defaults: defaults)
            let masksOwnHeader = DebugDrawerRedaction.none.adding(headers: ["X-Own-Secret"])
            let masksNothing = DebugDrawerRedaction.none
            drawer.redaction = masksOwnHeader
            var snapshot = NetworkSnapshot()
            snapshot.log.captured = [NetworkEntry(
                timestamp: Date(timeIntervalSince1970: 1_800_000_000), method: "GET", url: "https://api.example.com/v1/orders",
                host: "api.example.com", path: "/v1/orders",
                requestHeaders: ["Authorization": "Bearer shared-only", "X-Own-Secret": "own-only"],
                requestBody: nil, statusCode: 200, isComplete: true
            )]
            let sut = NetworkPluginContent(transport: DebugDrawerPluginTransport(
                initial: snapshot, snapshots: AsyncStream { $0.finish() }, send: { _ in }
            ))
            let expectedOwn: [String: String] = ["Authorization": "Bearer shared-only", "X-Own-Secret": DebugDrawerRedaction.mask]
            let expectedChanged: [String: String] = ["Authorization": "Bearer shared-only", "X-Own-Secret": "own-only"]
            var shownOwn: [String: String] = [:]
            var exportedOwn: DebugDrawerRedaction?
            var shownChanged: [String: String] = [:]
            var exportedChanged: DebugDrawerRedaction?

            try await ViewHosting.host(sut.environment(\.showingDrawer, drawer)) {
                try await sut.inspection.inspect { view in
                    let row = try view.find(NetworkRequestRow.self).actualView()
                    shownOwn = row.redaction.redacting(headers: row.entry.requestHeaders)
                    exportedOwn = try view.find(NetworkToolbar.self).actualView().export?.redaction
                }
                drawer.redaction = masksNothing
                try await sut.inspection.inspect { view in
                    let row = try view.find(NetworkRequestRow.self).actualView()
                    shownChanged = row.redaction.redacting(headers: row.entry.requestHeaders)
                    exportedChanged = try view.find(NetworkToolbar.self).actualView().export?.redaction
                }
            }

            #expect(shownOwn == expectedOwn)
            #expect(exportedOwn == masksOwnHeader)
            #expect(shownChanged == expectedChanged)
            #expect(exportedChanged == masksNothing)
        }
    }
#endif
