import Combine
import DebugDrawer
import Foundation

// The example host's side of a sidecar: sessions of at most five minutes, a registry gated by them
// offering one session-scoped capability (a log level), and an app-group store server for a
// sidecar app to reach it through. The example ships no sidecar app, so the test bench plays one:
// its Sidecar Session actions connect to the app's own store with the transport a sidecar uses and
// leave their commands there, so they take the path a sidecar's take, gate included. The iOS
// examples show an indicator while `sessions.snapshot` is active, styled their own way. The app
// also serves the socket a sidecar app connects to live, and a background keeper holds the app
// running while a session is open; the Start a Debug Session action is the person's action that, on
// iOS 26, asks for a continued processing task (`com.debugdrawer.example.ios.DebugDrawerSession.*`
// in the iOS example's BGTaskSchedulerPermittedIdentifiers). Everything compiles in release, where
// the sessions never open, the servers serve nothing, the keeper holds nothing and the actions'
// transport throws.

/// A sample capability: the log level a sidecar elevates for a session, which reverts as the
/// session ends.
@MainActor
public final class ExampleLogLevel: DebugDrawerPluginModel {
    public struct Snapshot: Codable, Equatable, Sendable {
        /// The level the app logs at.
        public var level = "info"
    }

    public enum Command: Codable, Equatable, Sendable {
        /// Logs everything down to debug.
        case elevate
        /// Logs at the default level.
        case reset
    }

    @Published public private(set) var snapshot = Snapshot()

    public func perform(_ command: Command) {
        switch command {
        case .elevate: snapshot.level = "debug"
        case .reset: snapshot.level = "info"
        }
    }
}

/// The example's sidecar receiver: its sessions, the capability they gate, and the store a sidecar
/// reaches them through.
@MainActor
public enum ExampleSidecar {
    /// The ID the log level is registered under, which the audit log names it by.
    public static let logLevelID = "Example.LogLevel"
    /// Sessions last at most five minutes, whatever a sidecar asks for.
    public static let sessions = DebugDrawerSessions(maximumDuration: 5 * 60)
    /// The sample capability.
    public static let logLevel = ExampleLogLevel()
    private static let registry = DebugDrawerModelRegistry(sessions: sessions)
    private static let server = DebugDrawerAppGroupStoreServer(registry: registry, directory: storeDirectory)
    /// The socket a sidecar app connects to while both run, beside the store.
    private static let socketServer = DebugDrawerSocketServer(
        registry: registry, socketPath: storeDirectory.appending(path: "drawer.sock").path
    )
    /// Keeps the app running in the background while a session is open, and ends the session as
    /// the sidecar disconnects from the socket.
    public static let keeper = DebugDrawerBackgroundKeeper(sessions: sessions, socketServer: socketServer)
    /// The test bench's stand-in for a sidecar app: a store transport, made on first use.
    private static var sidecar: (any DebugDrawerTransport)?
    /// What the stand-in sidecar connected to, held so its commands keep going out.
    private static var sessionTransport: DebugDrawerPluginTransport<DebugDrawerSessionState, DebugDrawerSessionCommand>?
    private static var logLevelTransport: DebugDrawerPluginTransport<ExampleLogLevel.Snapshot, ExampleLogLevel.Command>?
    private static var auditForwarding: AnyCancellable?
    private static var keeperLogging: AnyCancellable?

    /// The store's directory: in the app group's container when the app has the group, else in
    /// Caches, which serves the test bench's stand-in sidecar as well.
    private static var storeDirectory: URL {
        let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.debugdrawer.example")
            ?? URL.cachesDirectory
        return container.appending(path: "DebugDrawerSidecar", directoryHint: .isDirectory)
    }

    /// Registers the capability, starts serving the store, and forwards the audit log to the
    /// console, as a host would to its own log. Call it at launch; the actions call it too, for an
    /// example that doesn't, and later calls do nothing.
    public static func install() {
        guard auditForwarding == nil else { return }
        registry.register(logLevel, id: logLevelID, scope: .session(revertWith: .reset))
        auditForwarding = sessions.auditEntries.sink { entry in
            print("[Sidecar audit] \(entry.date) \(entry.capability) \(entry.event)")
        }
        do {
            try server.start()
        } catch {
            print("[Sidecar] The store server didn't start: \(error)")
        }
        do {
            try socketServer.start()
        } catch {
            print("[Sidecar] The socket server didn't start: \(error)")
        }
        // Follows the keeper's request in the console, so a run shows what it held.
        keeperLogging = keeper.$request.removeDuplicates().sink { request in
            print("[Sidecar] Background request: \(request)")
        }
    }

    /// Starts a five-minute session from the person's action, as a Start Debug Session button
    /// would, so the app keeps running when they switch to the sidecar: a continued processing
    /// task on iOS 26 and later, with the system's progress, else the platform's short request.
    static func startDebugSession() -> String {
        install()
        keeper.startSession(duration: 5 * 60, title: "Debug session", subtitle: "A sidecar app may drive this app")
        return "Started a session; holding \(keeper.request)"
    }

    /// Asks, as a sidecar would, for a session of `duration` seconds.
    static func openSession(duration: TimeInterval) async -> String {
        await send(.open(duration: duration))
    }

    /// Asks, as a sidecar would, to end the session.
    static func endSession() async -> String {
        await send(.end)
    }

    /// Asks, as a sidecar would, to elevate the log level: applied only within a session.
    static func elevateLogLevel() async -> String {
        do {
            if logLevelTransport == nil {
                logLevelTransport = try await connection().connect(
                    toPlugin: logLevelID, snapshot: ExampleLogLevel.Snapshot.self, command: ExampleLogLevel.Command.self
                )
            }
            logLevelTransport?.send(.elevate)
            return "Left elevate for \(logLevelID) in the store"
        } catch {
            return "Couldn't reach the store: \(error)"
        }
    }

    private static func send(_ command: DebugDrawerSessionCommand) async -> String {
        do {
            if sessionTransport == nil {
                sessionTransport = try await connection().connect(
                    toPlugin: DebugDrawerSessions.pluginID, snapshot: DebugDrawerSessionState.self, command: DebugDrawerSessionCommand.self
                )
            }
            sessionTransport?.send(command)
            return "Left \(command) in the store"
        } catch {
            return "Couldn't reach the store: \(error)"
        }
    }

    private static func connection() throws -> any DebugDrawerTransport {
        install()
        if let sidecar { return sidecar }
        let transport = try DebugDrawerAppGroupStoreTransport(directory: storeDirectory)
        sidecar = transport
        return transport
    }
}
