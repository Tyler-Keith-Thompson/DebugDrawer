@testable import DebugDrawerReceiver
import Foundation
import Testing

// The store's command budget, past which a viewer's trim removes the oldest files: the newest
// command for the sessions, a session's open queued before the app launched, stays wherever it
// sits, so what was queued after it still lands in its session (DD-296). Each test writes command
// files as a sidecar's transport names them (`<sequence>.json`, sorted by name) into a temporary
// app directory and trims.
@MainActor
@Suite
struct CommandTrimTests {
    @Test("Past the file budget the trim removes the oldest commands but keeps the newest one for the sessions")
    func keepsTheNewestSessionsCommand() throws {
        let layout = AppGroupStoreLayout(directory: FileManager.default.temporaryDirectory.appending(path: "CommandTrimTests-\(UUID().uuidString)"))
        #expect(layout.create())
        let limit = AppGroupStoreLayout.maximumCommandFiles
        let names = (0..<(limit + 10)).map { String(format: "%05d.json", $0) }
        for (index, name) in names.enumerated() {
            let pluginID = [0, 3].contains(index) ? DebugDrawerSessions.pluginID : "Shop.Tally"
            let message = TransportMessage(kind: .command, pluginID: pluginID, payload: Data("{}".utf8))
            try layout.write(StoreDocument(message).encoded(), to: layout.commands.appending(path: name))
        }
        let expected = ["00003.json"] + names.suffix(limit - 1)

        let removed = layout.trimCommands(keepingNewestFor: DebugDrawerSessions.pluginID)

        let actual = layout.messageFiles(in: layout.commands).map(\.lastPathComponent)
        #expect(removed == 10)
        #expect(actual == expected)
    }

    @Test("Within the budget the trim removes nothing")
    func withinBudgetRemovesNothing() throws {
        let layout = AppGroupStoreLayout(directory: FileManager.default.temporaryDirectory.appending(path: "CommandTrimTests-\(UUID().uuidString)"))
        #expect(layout.create())
        let message = TransportMessage(kind: .command, pluginID: "Shop.Tally", payload: Data("{}".utf8))
        for index in 0..<AppGroupStoreLayout.maximumCommandFiles {
            try layout.write(StoreDocument(message).encoded(), to: layout.commands.appending(path: String(format: "%05d.json", index)))
        }

        let removed = layout.trimCommands(keepingNewestFor: DebugDrawerSessions.pluginID)

        #expect(removed == 0)
        #expect(layout.messageFiles(in: layout.commands).count == AppGroupStoreLayout.maximumCommandFiles)
    }

    @Test("With no command for the sessions the trim removes the oldest first")
    func withoutSessionsCommandRemovesOldest() throws {
        let layout = AppGroupStoreLayout(directory: FileManager.default.temporaryDirectory.appending(path: "CommandTrimTests-\(UUID().uuidString)"))
        #expect(layout.create())
        let limit = AppGroupStoreLayout.maximumCommandFiles
        let names = (0...limit).map { String(format: "%05d.json", $0) }
        let message = TransportMessage(kind: .command, pluginID: "Shop.Tally", payload: Data("{}".utf8))
        for name in names {
            try layout.write(StoreDocument(message).encoded(), to: layout.commands.appending(path: name))
        }

        let removed = layout.trimCommands(keepingNewestFor: DebugDrawerSessions.pluginID)

        #expect(removed == 1)
        #expect(layout.messageFiles(in: layout.commands).map(\.lastPathComponent) == Array(names.dropFirst()))
    }
}
