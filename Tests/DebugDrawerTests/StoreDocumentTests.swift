#if DEBUG
    import Combine
    @testable import DebugDrawer
    @testable import DebugDrawerReceiver
    import Foundation
    import Testing

    /// A model whose snapshot is a count, changed by commands.
    @MainActor
    private final class CountModel: DebugDrawerPluginModel {
        struct Snapshot: Codable, Equatable, Sendable {
            var count = 0
        }

        enum Command: Codable, Equatable, Sendable {
            case add(Int)
        }

        @Published private(set) var snapshot = Snapshot()

        func perform(_ command: Command) {
            switch command {
            case let .add(amount): snapshot.count += amount
            }
        }
    }

    // The app-group store's documents: each carries its schema version and the hello of the build
    // that wrote it, an older one is migrated forward as it is read, and a newer one is read for the
    // keys this build knows. The last tests run the real store server and transport over files a
    // schema 1 build (a bare message) and a build two major versions ahead left in the directory.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct StoreDocumentTests {
        @Test("A document encodes its schema version and its writer beside the message's keys")
        func encodesSchemaAndWriter() throws {
            let sut = StoreDocument(TransportMessage(kind: .snapshot, pluginID: "Count", payload: Data("{}".utf8)))
            let expected = #"{"kind":"snapshot","payload":"e30=","pluginID":"Count","schemaVersion":2,"version":1,"#
                + #""writer":{"capabilities":["commands","unsubscribe","acknowledgements"],"oldestVersion":1,"version":2}}"#

            let actual = try String(bytes: sut.encoded(), encoding: .utf8)

            #expect(actual == expected)
            #expect(StoreDocument.currentSchemaVersion == 2)
        }

        @Test("A schema 1 document, a bare message, migrates to the current schema, written by protocol version 1")
        func schemaOneMigrates() throws {
            let schemaOne = Data(#"{"kind":"snapshot","payload":"e30=","pluginID":"Count","version":1}"#.utf8)
            let expectedMessage = TransportMessage(kind: .snapshot, pluginID: "Count", payload: Data("{}".utf8))

            let actual = try #require(StoreDocument.decoded(from: schemaOne))

            #expect(actual.schemaVersion == StoreDocument.currentSchemaVersion)
            #expect(actual.writer == TransportHello.firstVersion)
            #expect(actual.message == expectedMessage)
            #expect(actual.isReadable)
        }

        @Test("A reader of bare messages, as schema 1 builds are, reads a current document's message")
        func schemaOneReaderReadsCurrent() throws {
            let message = TransportMessage(kind: .command, pluginID: "Count", payload: Data("{}".utf8))

            let actual = try TransportMessage.decoded(from: StoreDocument(message).encoded())

            #expect(actual == message)
        }

        @Test("A current document decodes to what was encoded")
        func currentRoundTrips() throws {
            let expected = StoreDocument(TransportMessage(kind: .snapshot, pluginID: "Count", payload: Data("{}".utf8)))

            let actual = try StoreDocument.decoded(from: expected.encoded())

            #expect(actual == expected)
        }

        @Test("A newer schema's document, from a build one major version ahead, is read for the keys this build knows")
        func newerSchemaIsRead() throws {
            let newer = Data((#"{"checksum":"abc","kind":"snapshot","payload":"e30=","pluginID":"Count","schemaVersion":3,"version":1,"#
                    + #""writer":{"capabilities":["commands","deltaSnapshots"],"oldestVersion":2,"version":3}}"#).utf8)
            let expectedWriter = TransportHello(
                version: 3, oldestVersion: 2, capabilities: [.commands, TransportCapability(rawValue: "deltaSnapshots")]
            )

            let actual = try #require(StoreDocument.decoded(from: newer))

            #expect(actual.schemaVersion == 3)
            #expect(actual.writer == expectedWriter)
            #expect(actual.message.pluginID == "Count")
            #expect(actual.isReadable)
        }

        @Test("A document from a build two major versions ahead decodes but isn't readable")
        func twoVersionsAheadIsNotReadable() throws {
            let farAhead = Data((#"{"kind":"command","payload":"e30=","pluginID":"Count","schemaVersion":4,"version":1,"#
                    + #""writer":{"capabilities":["commands"],"oldestVersion":4,"version":4}}"#).utf8)

            let actual = try #require(StoreDocument.decoded(from: farAhead))

            #expect(!actual.isReadable)
        }

        @Test("A document of schema 2 on without a writer, of schema 0, or in another envelope format reads as nothing")
        func malformedDocuments() {
            let noWriter = Data(#"{"kind":"snapshot","payload":"","pluginID":"Count","schemaVersion":2,"version":1}"#.utf8)
            let schemaZero = Data(#"{"kind":"snapshot","payload":"","pluginID":"Count","schemaVersion":0,"version":1}"#.utf8)
            let otherEnvelope = Data(#"{"kind":"snapshot","payload":"","pluginID":"Count","version":2}"#.utf8)

            let actual = [noWriter, schemaZero, otherEnvelope].map(StoreDocument.decoded(from:))

            #expect(actual == [nil, nil, nil])
        }

        @Test("A viewer reads a snapshot file a schema 1 build left, and leaves its command in the current schema")
        func viewerReadsSchemaOneSnapshot() async throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: "StoreDocumentTests-\(UUID().uuidString)")
            let snapshots = AppGroupStoreLayout.appDirectory(inStore: directory).appending(path: "snapshots")
            let commands = AppGroupStoreLayout.appDirectory(inStore: directory).appending(path: "commands")
            try FileManager.default.createDirectory(at: snapshots, withIntermediateDirectories: true)
            let payload = try TransportMessage.payload(CountModel.Snapshot(count: 9))
            let schemaOne = Data(#"{"kind":"snapshot","payload":"\#(payload.base64EncodedString())","pluginID":"Count","version":1}"#.utf8)
            try schemaOne.write(to: snapshots.appending(path: "Count.json"))
            let connection = try DebugDrawerAppGroupStoreTransport(directory: AppGroupStoreLayout.appDirectory(inStore: directory))

            let sut = try await connection.connect(toPlugin: "Count", snapshot: CountModel.Snapshot.self, command: CountModel.Command.self)
            sut.send(.add(1))

            let files = try FileManager.default.contentsOfDirectory(at: commands, includingPropertiesForKeys: nil)
            let left = try StoreDocument.decoded(from: Data(contentsOf: #require(files.first)))
            #expect(sut.snapshot == CountModel.Snapshot(count: 9))
            #expect(files.count == 1)
            #expect(left?.schemaVersion == StoreDocument.currentSchemaVersion)
            #expect(left?.writer == TransportHello.current)
            #expect(left?.message.kind == .command)
        }

        @Test("The app performs a schema 1 build's command, skips one from two major versions ahead, and writes its snapshot in the current schema")
        func appReadsOldCommandsAndSkipsIncompatible() async throws {
            let model = CountModel()
            let registry = DebugDrawerModelRegistry()
            registry.register(model, id: "Count")
            let directory = FileManager.default.temporaryDirectory.appending(path: "StoreDocumentTests-\(UUID().uuidString)")
            let commands = AppGroupStoreLayout.appDirectory(inStore: directory).appending(path: "commands")
            try FileManager.default.createDirectory(at: commands, withIntermediateDirectories: true)
            let addHundred = try TransportMessage.payload(CountModel.Command.add(100)).base64EncodedString()
            let addTwo = try TransportMessage.payload(CountModel.Command.add(2)).base64EncodedString()
            let farAhead = #"{"kind":"command","payload":"\#(addHundred)","pluginID":"Count","schemaVersion":4,"version":1,"#
                + #""writer":{"capabilities":["commands"],"oldestVersion":4,"version":4}}"#
            let schemaOne = #"{"kind":"command","payload":"\#(addTwo)","pluginID":"Count","version":1}"#
            try Data(farAhead.utf8).write(to: commands.appending(path: "1-ahead.json"))
            try Data(schemaOne.utf8).write(to: commands.appending(path: "2-old.json"))
            let server = DebugDrawerAppGroupStoreServer(registry: registry, directory: directory)

            try server.start()
            let viewer = try await DebugDrawerAppGroupStoreTransport(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
                .connect(toPlugin: "Count", snapshot: CountModel.Snapshot.self, command: CountModel.Command.self)
            for await snapshot in viewer.snapshots() where snapshot.count >= 2 {
                break
            }
            server.stop()

            let remaining = try FileManager.default.contentsOfDirectory(atPath: commands.path)
            let written = try StoreDocument.decoded(from: Data(contentsOf: server.appDirectory.appending(path: "snapshots/Count.json")))
            #expect(model.snapshot.count == 2)
            #expect(viewer.snapshot.count == 2)
            #expect(remaining.isEmpty)
            #expect(written?.schemaVersion == StoreDocument.currentSchemaVersion)
            #expect(written?.writer == TransportHello.current)
        }
    }
#endif
