import DebugDrawer
import DebugDrawerReceiver
import DebugDrawerSidecarKit
import ExampleSidecarStore
import Foundation
import os
import SwiftUI

// `-PrepareLaunch <bundle ID>`: the sidecar prepares a session and a flag override for that app's
// next launch on its own, without anyone at the screen, so a run shows the tester's flow (DD-296):
// the sidecar first, then the app. Once the app is listed, it prepares the flags from what it read
// of them before; if it never read them, it reads them now from the running app, in a session it
// opens and ends, and asks for the app to be stopped and the sidecar launched with the argument
// again. With the flags prepared, it leaves a session's open (with a grant from the example's
// grant server) and an override of `new-checkout` to true in the app's store, and logs that both
// wait for the launch. When the app launches it performs them; the script logs the session the
// app opened and the override the app's own snapshot then reports, and ends the session. Each
// step waits on an event (the list, the published wait, the flags' snapshots), not on a clock,
// and is logged (subsystem com.debugdrawer.example.sidecar, category PrepareLaunch).

/// Prepares a session and a flag override for an app's next launch when the sidecar is launched
/// with `-PrepareLaunch <bundle ID>`.
@MainActor
enum ExamplePrepareScript {
    private static let logger = Logger(subsystem: "com.debugdrawer.example.sidecar", category: "PrepareLaunch")
    /// The flag the script overrides, which the example host lists as overridable.
    private static let flagKey = "new-checkout"
    private static var running: Task<Void, Never>?

    /// Starts the script when the launch arguments ask for it; does nothing otherwise.
    static func startIfAsked(arguments: [String] = ProcessInfo.processInfo.arguments) {
        guard let index = arguments.firstIndex(of: "-PrepareLaunch"), arguments.indices.contains(index + 1) else { return }
        let bundleIdentifier = arguments[index + 1]
        running = Task { await run(with: bundleIdentifier) }
    }

    private static func run(with bundleIdentifier: String) async {
        logger.notice("Waiting for \(bundleIdentifier, privacy: .public) to be listed")
        let list = DebugDrawerSidecarAppList(storeDirectory: ExampleSidecarStore.directory)
        var listed: DebugDrawerSidecarApp?
        for await apps in list.$apps.values {
            if let app = apps.first(where: { $0.bundleIdentifier == bundleIdentifier }) {
                listed = app
                break
            }
        }
        guard let app = listed else { return }
        logger.notice("Listed \(bundleIdentifier, privacy: .public), running: \(app.isRunning, privacy: .public)")
        do {
            let flags = FlagsHandle()
            let connection = try DebugDrawerSidecarConnection(app: app)
            defer { connection.close() }
            do {
                _ = try connection.prepare(flags.plugin)
            } catch {
                logger.notice("The flags were never read: reading them from the running app")
                try await read(flags, over: connection, of: app)
                logger.notice("Read the flags. Stop \(bundleIdentifier, privacy: .public), then launch the sidecar with -PrepareLaunch again")
                return
            }
            try await prepare(flags, over: connection, of: app)
        } catch {
            logger.error("Script failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Reads the flags once, in a session, so the sidecar keeps them for preparing.
    private static func read(_ flags: FlagsHandle, over connection: DebugDrawerSidecarConnection, of app: DebugDrawerSidecarApp) async throws {
        connection.openSession(duration: 60, grant: try ExampleGrantServer.grant(for: app))
        let sessions = try await sessionsTransport(of: connection)
        _ = try await first(of: sessions) { $0.session }
        _ = try await connection.host(flags.plugin)
        sessions.send(.end)
        _ = try await first(of: sessions) { $0.isActive ? nil : true }
    }

    /// Leaves the open and the override for the launch, and follows them into the session.
    private static func prepare(_ flags: FlagsHandle, over connection: DebugDrawerSidecarConnection, of app: DebugDrawerSidecarApp) async throws {
        let transport = try flags.transport()
        let shown = String(describing: transport.snapshot.flags.first { $0.key == flagKey }?.value)
        logger.notice("Prepared the flags from what was read before: \(flagKey, privacy: .public) = \(shown, privacy: .public)")
        connection.openSession(duration: 5 * 60, grant: try ExampleGrantServer.grant(for: app))
        transport.send(.setOverride(key: flagKey, value: .bool(true)))
        let isWaiting = connection.isWaitingForLaunch
        logger.notice("Left the open and setOverride \(flagKey, privacy: .public) = true; waiting for launch: \(isWaiting, privacy: .public)")
        for await waiting in connection.$isWaitingForLaunch.values where !waiting {
            break
        }
        logger.notice("The app took the open")
        let sessions = try await sessionsTransport(of: connection)
        let session = try await first(of: sessions) { $0.session }
        logger.notice("Session \(session.id.uuidString, privacy: .public) opened at launch, until \(session.expires, privacy: .public)")
        let overridden = try await first(of: transport) { snapshot in
            snapshot.overriddenKeys.contains(flagKey) ? snapshot.flags.first { $0.key == flagKey } : nil
        }
        let live = connection.preparedForLaunch.isEmpty
        let value = String(describing: overridden.value)
        logger.notice("Host reports \(overridden.key, privacy: .public) = \(value, privacy: .public), overridden; live: \(live, privacy: .public)")
        sessions.send(.end)
        _ = try await first(of: sessions) { $0.isActive ? nil : true }
        logger.notice("Session \(session.id.uuidString, privacy: .public) ended")
    }

    /// The app's sessions, once read.
    private static func sessionsTransport(
        of connection: DebugDrawerSidecarConnection
    ) async throws -> DebugDrawerPluginTransport<DebugDrawerSessionState, DebugDrawerSessionCommand> {
        for await sessions in connection.$sessions.values {
            if let sessions { return sessions }
        }
        throw CancellationError()
    }

    /// The first value `match` finds in the transport's snapshots, the current one first.
    private static func first<Snapshot, Command, Value>(
        of transport: DebugDrawerPluginTransport<Snapshot, Command>,
        where match: (Snapshot) -> Value?
    ) async throws -> Value {
        for await snapshot in transport.snapshots() {
            if let value = match(snapshot) { return value }
        }
        // The stream ends only when the task is cancelled or the transport goes.
        throw CancellationError()
    }
}

/// The flags as a sidecar plugin that hands the script its transport.
@MainActor
private final class FlagsHandle {
    typealias Transport = DebugDrawerPluginTransport<DebugDrawerFeatureFlagOverrides.Snapshot, DebugDrawerFeatureFlagOverrides.Command>

    private var made: Transport?

    /// The flags plugin, keeping the transport it is made over.
    lazy var plugin = DebugDrawerSidecarPlugin(
        id: DebugDrawerFeatureFlagOverrides.pluginID, title: "Flags", icon: "flag",
        snapshot: DebugDrawerFeatureFlagOverrides.Snapshot.self, command: DebugDrawerFeatureFlagOverrides.Command.self
    ) { [weak self] transport in
        self?.made = transport
        return ScriptPlugin()
    }

    /// The transport the plugin was made over.
    func transport() throws -> Transport {
        guard let made else { throw CancellationError() }
        return made
    }
}

/// Draws nothing: the script drives the transport.
private struct ScriptPlugin: DebugDrawerPlugin {
    var title = "Flags"
    var icon = "flag"

    var body: some View {
        EmptyView()
    }
}
