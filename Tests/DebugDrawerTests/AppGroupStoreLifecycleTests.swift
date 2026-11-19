#if DEBUG
    import Combine
    @testable import DebugDrawer
    import Foundation
    import Testing
    #if os(macOS)
        import AppKit
    #elseif canImport(UIKit)
        import UIKit
    #endif

    /// A model whose snapshot is a tally and a note, changed by commands.
    @MainActor
    private final class TallyModel: DebugDrawerPluginModel {
        struct Snapshot: Codable, Equatable, Sendable {
            var count = 0
            var note = ""
        }

        enum Command: Codable, Equatable, Sendable {
            case add(Int)
            case note(String)
        }

        @Published private(set) var snapshot = Snapshot()

        func perform(_ command: Command) {
            switch command {
            case let .add(amount): snapshot.count += amount
            case let .note(text): snapshot.note = text
            }
        }
    }

    // The app-group store over an app's life: what a suspended app does with the overrides left
    // for it once it comes back, and how much the store keeps. The directory is a temporary one
    // standing in for the app group's container; the foreground is the notification the system
    // posts, posted here by hand.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct AppGroupStoreLifecycleTests {
        @Test("An override left while the app is suspended is performed as it comes to the foreground, before the notification's post returns")
        func foregroundPerformsWaitingCommands() async throws {
            let model = TallyModel()
            let registry = DebugDrawerModelRegistry()
            registry.register(model, id: "Tally")
            let directory = FileManager.default.temporaryDirectory.appending(path: "AppGroupStoreLifecycleTests-\(UUID().uuidString)")
            let server = DebugDrawerAppGroupStoreServer(registry: registry, directory: directory)
            try server.start()
            let connection = try DebugDrawerAppGroupStoreTransport(directory: directory)
            let viewer = try await connection.connect(toPlugin: "Tally", snapshot: TallyModel.Snapshot.self, command: TallyModel.Command.self)
            #if os(macOS)
                let foreground = NSApplication.willBecomeActiveNotification
            #else
                let foreground = UIApplication.willEnterForegroundNotification
            #endif
            let expected = TallyModel.Snapshot(note: "override")

            // Nothing awaits from here on, so the app's main actor runs none of its own work, as
            // for an app the system has suspended: the store's own wake-up can't perform the
            // override, only the foreground can.
            viewer.send(.note("override"))
            let whileSuspended = model.snapshot
            NotificationCenter.default.post(name: foreground, object: nil)
            let actual = model.snapshot

            #expect(whileSuspended == TallyModel.Snapshot())
            #expect(actual == expected)
            server.stop()
        }

        @Test("A stopped server performs nothing as the app comes to the foreground; the override waits for it to start")
        func stoppedServerIgnoresForeground() async throws {
            let model = TallyModel()
            let registry = DebugDrawerModelRegistry()
            registry.register(model, id: "Tally")
            let directory = FileManager.default.temporaryDirectory.appending(path: "AppGroupStoreLifecycleTests-\(UUID().uuidString)")
            let server = DebugDrawerAppGroupStoreServer(registry: registry, directory: directory)
            try server.start()
            let connection = try DebugDrawerAppGroupStoreTransport(directory: directory)
            let viewer = try await connection.connect(toPlugin: "Tally", snapshot: TallyModel.Snapshot.self, command: TallyModel.Command.self)
            server.stop()
            #if os(macOS)
                let foreground = NSApplication.willBecomeActiveNotification
            #else
                let foreground = UIApplication.willEnterForegroundNotification
            #endif
            let commands = directory.appending(path: "commands")

            viewer.send(.note("override"))
            NotificationCenter.default.post(name: foreground, object: nil)
            let actual = model.snapshot
            let waiting = try FileManager.default.contentsOfDirectory(atPath: commands.path)

            #expect(actual == TallyModel.Snapshot())
            #expect(waiting.count == 1)
        }

        @Test("Commands waiting for the app are capped at maximumCommandFiles, a cut-off file among them: leaving more removes the oldest first")
        func commandFilesAreCapped() async throws {
            let model = TallyModel()
            let registry = DebugDrawerModelRegistry()
            registry.register(model, id: "Tally")
            let directory = FileManager.default.temporaryDirectory.appending(path: "AppGroupStoreLifecycleTests-\(UUID().uuidString)")
            let commands = directory.appending(path: "commands")
            let server = DebugDrawerAppGroupStoreServer(registry: registry, directory: directory)
            try server.start()
            let connection = try DebugDrawerAppGroupStoreTransport(directory: directory)
            let viewer = try await connection.connect(toPlugin: "Tally", snapshot: TallyModel.Snapshot.self, command: TallyModel.Command.self)
            server.stop()
            // What a viewer killed mid-write leaves: its name sorts before every command's.
            let cutOffName = "00000000000000000000-0000000001-cut.json.4C3F0E0A-6D47-4A9B-8C1F-2E5D7B9A1C30.partial"
            try Data(#"{"kind":"comm"#.utf8).write(to: commands.appending(path: cutOffName))
            let limit = AppGroupStoreLayout.maximumCommandFiles
            let sent = 1...(limit + 10)
            // The cut-off file and commands 1 to 10 are the eleven oldest.
            let expectedCount = (11...(limit + 10)).reduce(0, +)

            for amount in sent {
                viewer.send(.add(amount))
            }
            let waiting = try FileManager.default.contentsOfDirectory(atPath: commands.path)
            try server.start()
            for await snapshot in model.$snapshot.values where snapshot.count >= expectedCount {
                break
            }

            #expect(waiting.count == limit)
            #expect(!waiting.contains(cutOffName))
            #expect(model.snapshot.count == expectedCount)
            server.stop()
        }

        @Test("Commands waiting for the app are capped at maximumCommandBytes: leaving more removes the oldest first")
        func commandBytesAreCapped() async throws {
            let model = TallyModel()
            let registry = DebugDrawerModelRegistry()
            registry.register(model, id: "Tally")
            let directory = FileManager.default.temporaryDirectory.appending(path: "AppGroupStoreLifecycleTests-\(UUID().uuidString)")
            let commands = directory.appending(path: "commands")
            let server = DebugDrawerAppGroupStoreServer(registry: registry, directory: directory)
            try server.start()
            let connection = try DebugDrawerAppGroupStoreTransport(directory: directory)
            let viewer = try await connection.connect(toPlugin: "Tally", snapshot: TallyModel.Snapshot.self, command: TallyModel.Command.self)
            server.stop()
            // Base64 makes each document about a third larger than its note: three fit, four don't.
            let noteLength = AppGroupStoreLayout.maximumCommandBytes / 5
            let letters: [Character] = ["a", "b", "c", "d", "e"]
            let expected: [Character?] = ["c", "d", "e"]

            for letter in letters {
                viewer.send(.note(String(repeating: letter, count: noteLength)))
            }
            let files = try FileManager.default.contentsOfDirectory(at: commands, includingPropertiesForKeys: [.fileSizeKey])
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            let bytes = try files.reduce(0) { $0 + (try $1.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) }
            let actual: [Character?] = try files.map { file in
                let document = try #require(StoreDocument.decoded(from: Data(contentsOf: file)))
                guard case let .note(text) = try JSONDecoder().decode(TallyModel.Command.self, from: document.message.payload) else { return nil }
                return text.first
            }

            #expect(actual == expected)
            #expect(bytes <= AppGroupStoreLayout.maximumCommandBytes)
        }

        @Test("A command larger than maximumCommandBytes isn't left in the store at all")
        func oversizedCommandIsNotLeft() async throws {
            let model = TallyModel()
            let registry = DebugDrawerModelRegistry()
            registry.register(model, id: "Tally")
            let directory = FileManager.default.temporaryDirectory.appending(path: "AppGroupStoreLifecycleTests-\(UUID().uuidString)")
            let commands = directory.appending(path: "commands")
            let server = DebugDrawerAppGroupStoreServer(registry: registry, directory: directory)
            try server.start()
            let connection = try DebugDrawerAppGroupStoreTransport(directory: directory)
            let viewer = try await connection.connect(toPlugin: "Tally", snapshot: TallyModel.Snapshot.self, command: TallyModel.Command.self)
            server.stop()

            viewer.send(.note(String(repeating: "x", count: AppGroupStoreLayout.maximumCommandBytes)))
            let actual = try FileManager.default.contentsOfDirectory(atPath: commands.path)

            #expect(actual.isEmpty)
        }

        @Test("The app's server, as it starts, removes what cut-off writes left among the snapshots and keeps every snapshot file")
        func startRemovesCutOffSnapshots() throws {
            let registry = DebugDrawerModelRegistry()
            let directory = FileManager.default.temporaryDirectory.appending(path: "AppGroupStoreLifecycleTests-\(UUID().uuidString)")
            let snapshots = directory.appending(path: "snapshots")
            try FileManager.default.createDirectory(at: snapshots, withIntermediateDirectories: true)
            try Data(#"{"kind":"snap"#.utf8).write(to: snapshots.appending(path: "Tally.json.4C3F0E0A-6D47-4A9B-8C1F-2E5D7B9A1C30.partial"))
            try Data("left".utf8).write(to: snapshots.appending(path: ".Tally.json"))
            try Data("{}".utf8).write(to: snapshots.appending(path: "Other.json"))
            let sut = DebugDrawerAppGroupStoreServer(registry: registry, directory: directory)
            let expected = ["Other.json"]

            try sut.start()
            let actual = try FileManager.default.contentsOfDirectory(atPath: snapshots.path).sorted()

            #expect(actual == expected)
            sut.stop()
        }
    }
#endif
