#if DEBUG && os(macOS)
    import DebugDrawer
    @testable import DebugDrawerReceiver
    @testable import DebugDrawerSidecarKit
    import Foundation
    import SwiftUI
    import Testing

    // DD-269: the connection finds a plugin it hosted by the `DebugDrawerSidecarPlugin.id` it was
    // asked for, not by the made plugin's own `id`, which here is its type's default and differs
    // from the model's ID. The app's model is served by a store server in a temporary group
    // container; each made plugin is numbered in its title, so a test can tell which one it got.

    /// The app's model: one count, never changed.
    @MainActor
    private final class RehostedCounterModel: DebugDrawerPluginModel {
        struct Snapshot: Codable, Equatable, Sendable { var count = 7 }
        enum Command: Codable, Sendable { case reset }

        var snapshot: Snapshot { Snapshot() }
        func perform(_ command: Command) {}
    }

    /// Counts the plugins made and the report contributions they add.
    @MainActor
    private final class RehostedCounts {
        var made = 0
        var contributions = 0
    }

    /// A sidecar plugin over the counter, keeping the default `id` (its type name).
    private struct RehostedCounterPlugin: DebugDrawerPlugin, DebugDrawerReportContributor {
        let transport: DebugDrawerPluginTransport<RehostedCounterModel.Snapshot, RehostedCounterModel.Command>
        let counts: RehostedCounts
        let title: String
        let icon = "number"

        var body: some View {
            Text("\(transport.snapshot.count)")
        }

        func contribute(to report: inout DebugDrawerReport, redaction: DebugDrawerRedaction) {
            counts.contributions += 1
            report.add(text: "count \(transport.snapshot.count)", named: "counter")
        }
    }

    /// The app's side, serving the counter, and a connection to it.
    @MainActor
    private struct RehostedPair {
        let store: URL
        let server: DebugDrawerAppGroupStoreServer
        let connection: DebugDrawerSidecarConnection

        func close() {
            connection.close()
            server.stop()
        }
    }

    @MainActor
    @Suite(.timeLimit(.minutes(1)), .serialized)
    struct SidecarRehostingTests {
        static let modelID = "SidecarRehostingTests.Counter"

        private static func counter(_ counts: RehostedCounts) -> DebugDrawerSidecarPlugin {
            DebugDrawerSidecarPlugin(
                id: modelID, title: "Counter", icon: "number",
                snapshot: RehostedCounterModel.Snapshot.self, command: RehostedCounterModel.Command.self
            ) { transport in
                counts.made += 1
                return RehostedCounterPlugin(transport: transport, counts: counts, title: "Counter \(counts.made)")
            }
        }

        private static func pair() throws -> RehostedPair {
            let store = FileManager.default.temporaryDirectory
                .appending(path: "SidecarRehostingTests-\(UUID().uuidString)")
                .appending(path: "DebugDrawer")
            let registry = DebugDrawerModelRegistry()
            registry.register(RehostedCounterModel(), id: modelID)
            let server = DebugDrawerAppGroupStoreServer(registry: registry, directory: store)
            server.identity = AppPresence.Identity(bundleIdentifier: "com.example.shop", displayName: "Shop", version: "2.4", build: "881")
            try server.start()
            let listed = try #require(DebugDrawerSidecarAppList(storeDirectory: store).apps.first)
            return try RehostedPair(store: store, server: server, connection: DebugDrawerSidecarConnection(app: listed))
        }

        @Test("Hosting a plugin twice returns the first and keeps one copy, though the made plugin's ID differs from the sidecar plugin's")
        func hostingTwiceKeepsTheFirst() async throws {
            let pair = try Self.pair()
            defer { pair.close() }
            let counts = RehostedCounts()

            let first = try await pair.connection.host(Self.counter(counts))
            let second = try await pair.connection.host(Self.counter(counts))

            #expect(first.id != Self.modelID)
            #expect(first.title == "Counter 1")
            #expect(second.title == "Counter 1")
            #expect(pair.connection.hosted.map(\.title) == ["Counter 1"])
            #expect(counts.made == 1)
        }

        @Test("Two concurrent host calls both return the plugin the first made, and one copy stays hosted")
        func concurrentHostCallsKeepOne() async throws {
            let pair = try Self.pair()
            defer { pair.close() }
            let counts = RehostedCounts()
            let connection = pair.connection

            let one = Task { @MainActor in try await connection.host(Self.counter(counts)).title }
            let other = Task { @MainActor in try await connection.host(Self.counter(counts)).title }
            let titles = try await [one.value, other.value]

            let kept = try #require(connection.hosted.first)
            #expect(connection.hosted.count == 1)
            #expect(titles == [kept.title, kept.title])
            #expect(kept.id != Self.modelID)
        }

        @Test("After repeated host calls the report holds the plugin's contribution once")
        func reportHoldsTheContributionOnce() async throws {
            let pair = try Self.pair()
            defer { pair.close() }
            let counts = RehostedCounts()
            let plugin = Self.counter(counts)
            _ = try await pair.connection.host(plugin)
            _ = try await pair.connection.host(plugin)
            _ = try await pair.connection.host(Self.counter(counts))
            let reports = pair.store.deletingLastPathComponent().appending(path: "Reports")

            let archive = try pair.connection.createReport(in: reports)

            let unzipped = reports.appending(path: "unzipped")
            let unzip = Process()
            unzip.executableURL = URL(filePath: "/usr/bin/ditto")
            unzip.arguments = ["-x", "-k", archive.path, unzipped.path]
            try unzip.run()
            unzip.waitUntilExit()
            let folder = try #require(try FileManager.default.contentsOfDirectory(at: unzipped, includingPropertiesForKeys: nil).first)
            let folders = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasPrefix("Counter") }
            let counter = try String(contentsOf: folder.appending(path: "Counter 1/counter.txt"), encoding: .utf8)

            #expect(counts.contributions == 1)
            #expect(folders == ["Counter 1"])
            #expect(counter == "count 7")
        }
    }
#endif
