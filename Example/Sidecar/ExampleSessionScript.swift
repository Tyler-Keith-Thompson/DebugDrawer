import Combine
import DebugDrawer
import DebugDrawerReceiver
import DebugDrawerSidecarKit
import ExampleSidecarStore
import Foundation
import os

// `-ScriptSession <bundle ID>`: the sidecar drives one session with that app on its own, without
// anyone at the screen, so a run shows a sidecar's commands reaching the host live (DD-105, where
// the Mac's screen may be locked and accessibility sees no windows). Once the app is listed it
// opens a session with a grant from the example's grant server, overrides the feature flag
// `new-checkout` to true, waits for the host to report the override, ends the session and waits
// for the host to put the flag back. Each step waits on the host's snapshot of it, not on a clock,
// and is logged (subsystem com.debugdrawer.example.sidecar, category SessionScript) with the
// channel that carried it, as is each switch of channel; the host audits the same steps in its own
// log (category Sidecar). The window shows the kit's view as usual.

/// Drives a session with one app when the sidecar is launched with `-ScriptSession <bundle ID>`.
@MainActor
enum ExampleSessionScript {
    private static let logger = Logger(subsystem: "com.debugdrawer.example.sidecar", category: "SessionScript")
    /// The flag the script overrides, which the example host lists as overridable.
    private static let flagKey = "new-checkout"
    private static var running: Task<Void, Never>?
    private static var channelLogging: AnyCancellable?

    /// Starts the script when the launch arguments ask for it; does nothing otherwise.
    static func startIfAsked(arguments: [String] = ProcessInfo.processInfo.arguments) {
        guard let index = arguments.firstIndex(of: "-ScriptSession"), arguments.indices.contains(index + 1) else { return }
        let bundleIdentifier = arguments[index + 1]
        running = Task { await run(with: bundleIdentifier) }
    }

    private static func run(with bundleIdentifier: String) async {
        logger.notice("Waiting for \(bundleIdentifier, privacy: .public) in \(ExampleSidecarStore.directory.path, privacy: .public)")
        let list = DebugDrawerSidecarAppList(storeDirectory: ExampleSidecarStore.directory)
        var listed: DebugDrawerSidecarApp?
        for await apps in list.$apps.values {
            if let app = apps.first(where: { $0.bundleIdentifier == bundleIdentifier }) {
                listed = app
                break
            }
        }
        guard let app = listed else { return }
        do {
            let transport = try DebugDrawerSidecarTransport(socketPath: app.socketPath, storeDirectory: app.storeDirectory)
            channelLogging = transport.$channel.sink { channel in
                logger.notice("Channel: \(String(describing: channel), privacy: .public)")
            }
            try await drive(app, over: transport)
            transport.close()
        } catch {
            logger.error("Script failed: \(String(describing: error), privacy: .public)")
        }
    }

    private static func drive(_ app: DebugDrawerSidecarApp, over transport: DebugDrawerSidecarTransport) async throws {
        let sessions = try await transport.connect(
            toPlugin: DebugDrawerSessions.pluginID, snapshot: DebugDrawerSessionState.self, command: DebugDrawerSessionCommand.self
        )
        let flags = try await transport.connect(
            toPlugin: DebugDrawerFeatureFlagOverrides.pluginID,
            snapshot: DebugDrawerFeatureFlagOverrides.Snapshot.self,
            command: DebugDrawerFeatureFlagOverrides.Command.self
        )
        logger.notice("Connected to \(app.bundleIdentifier, privacy: .public) over \(String(describing: transport.channel), privacy: .public)")

        sessions.send(.open(duration: 5 * 60, grant: try ExampleGrantServer.grant(for: app)))
        logger.notice("Sent open over \(String(describing: transport.channel), privacy: .public)")
        let session = try await first(of: sessions) { $0.session }
        logger.notice("Session \(session.id.uuidString, privacy: .public) opened, until \(session.expires, privacy: .public)")

        flags.send(.setOverride(key: flagKey, value: .bool(true)))
        logger.notice("Sent setOverride \(flagKey, privacy: .public) = true over \(String(describing: transport.channel), privacy: .public)")
        let overridden = try await first(of: flags) { snapshot in
            snapshot.flags.first { $0.key == flagKey && $0.value == .bool(true) && snapshot.overriddenKeys.contains(flagKey) }
        }
        logger.notice("Host reports \(overridden.key, privacy: .public) = \(String(describing: overridden.value), privacy: .public), overridden")

        sessions.send(.end)
        logger.notice("Sent end over \(String(describing: transport.channel), privacy: .public)")
        _ = try await first(of: sessions) { $0.isActive ? nil : true }
        let reverted = try await first(of: flags) { snapshot in
            snapshot.overriddenKeys.isEmpty ? snapshot.flags.first { $0.key == flagKey } : nil
        }
        let value = String(describing: reverted.value)
        logger.notice("Session ended; host reports \(reverted.key, privacy: .public) = \(value, privacy: .public), no override")
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
