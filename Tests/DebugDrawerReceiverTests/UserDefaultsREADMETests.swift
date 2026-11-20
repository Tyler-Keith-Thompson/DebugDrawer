// The README's "Allowlisted UserDefaults in production" example, verbatim, so the README cannot
// drift from the code: three keys allowlisted, the audit's changes forwarded to the app's log, an
// edit left in the store by a sidecar, the view that reads the key, and the key back as the
// session ends.
import Combine
@testable import DebugDrawerReceiver
import Foundation
import os
import SwiftUI
import Testing

@MainActor
private final class ProductionDefaults {
    private static let logger = Logger(subsystem: "com.example.MyApp", category: "Sidecar")
    let sessions = DebugDrawerSessions(maximumDuration: 15 * 60)
    let receiver: DebugDrawerReceiver
    private var auditForwarding: AnyCancellable?

    init(container: URL) throws {
        receiver = DebugDrawerReceiver(directory: container.appending(path: "DebugDrawer"), sessions: sessions)
        receiver.enable(.userDefaults(
            .choice("plan", title: "Plan", options: ["free", "pro"]),
            .bool("showsTips", title: "Shows Tips"),
            .integer("itemsPerPage", title: "Items per Page", in: 10 ... 100)
        ))
        auditForwarding = sessions.auditEntries.sink { entry in
            for change in entry.changes ?? [] {
                Self.logger.notice("Sidecar changed \(change.key, privacy: .public)")
            }
        }
        try receiver.start()
    }
}

private struct TipsBanner: View {
    @AppStorage("showsTips") private var showsTips = false

    var body: some View {
        if showsTips {
            Text("Tip: drag a row to reorder it.")
        }
    }
}

// Run serialized: the README's keys are in the standard defaults, as an app's are.
@MainActor
@Suite(.timeLimit(.minutes(1)), .serialized)
struct UserDefaultsREADMETests {
    @Test("README: a sidecar's edit of an allowlisted key changes what the app reads, is audited with its values, and ends with the session")
    func readmeUserDefaults() throws {
        let container = FileManager.default.temporaryDirectory.appending(path: "READMEUserDefaults-\(UUID().uuidString)")
        defer {
            for key in ["plan", "showsTips", "itemsPerPage", DebugDrawerUserDefaults.originalValuesDefaultsKey] {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        let app = try ProductionDefaults(container: container)
        defer { app.receiver.stop() }
        app.sessions.perform(.open(duration: 300))
        let layout = AppGroupStoreLayout(directory: app.receiver.appDirectory)
        let payload = try TransportMessage.payload(DebugDrawerUserDefaults.Command.set(key: "showsTips", value: .bool(true)))
        let document = StoreDocument(TransportMessage(kind: .command, pluginID: DebugDrawerUserDefaults.pluginID, payload: payload))
        try layout.write(document.encoded(), to: layout.commands.appending(path: "0.json"))
        _ = TipsBanner()
        let expectedChanges = [DebugDrawerAuditEntry.Change(key: "showsTips", oldValue: nil, newValue: .bool(true))]

        app.receiver.reevaluateGates()
        let duringSession = UserDefaults.standard.bool(forKey: "showsTips")
        let applied = app.sessions.auditLog.last
        app.sessions.end()

        #expect(duringSession)
        #expect(applied?.event == .commandApplied)
        #expect(applied?.changes == expectedChanges)
        #expect(UserDefaults.standard.object(forKey: "showsTips") == nil)
    }
}
