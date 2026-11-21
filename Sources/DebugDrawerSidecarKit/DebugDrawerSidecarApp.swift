import DebugDrawer
import Foundation

/// An app in the group that serves a sidecar, as its presence file in the store describes it: a
/// production app's `DebugDrawerReceiver`, or a debug build's `DebugDrawerAppGroupStoreServer`.
///
/// It holds nothing secret: who the app is, what it serves, the protocol it speaks and when it last
/// said so. A ``DebugDrawerSidecarAppList`` lists one for each app serving the group's store, each
/// with its own directory of the store, so the sidecar's connection to one app reads that app's
/// snapshots and leaves commands for it alone.
public struct DebugDrawerSidecarApp: Identifiable, Equatable, Sendable {
    /// The app's bundle identifier.
    public let bundleIdentifier: String
    /// The name the app shows.
    public let displayName: String
    /// The app's version (`CFBundleShortVersionString`), or empty.
    public let version: String
    /// The app's build (`CFBundleVersion`), or empty.
    public let build: String
    /// The IDs the app serves, sorted: its capabilities or plugin models, and
    /// `DebugDrawerSessions.pluginID` when its commands act only within a session.
    public let capabilities: [String]
    /// The major version of the protocol the app's store and socket speak. A sidecar reaches an
    /// app one major version apart from its own build; two apart, its transports throw
    /// `DebugDrawerTransportError.incompatibleVersion`.
    public let protocolVersion: Int
    /// When the app last said it serves: as it started, as what it serves changed, or as it came
    /// to the foreground. An app that was killed keeps the time it was last seen.
    public let lastSeen: Date
    /// The app's own directory of the group's store, `DebugDrawer/apps/<bundle ID>` in the
    /// container, where the app keeps its presence file and snapshots and takes commands.
    public let storeDirectory: URL
    /// Whether the app serves its capabilities' snapshots only within a session, as a production
    /// app's receiver does: before one opens, and once it ends, the sidecar has nothing current
    /// of them to show.
    var servesInSessionsOnly = false

    /// An app serving its directory of the group's store, `storeDirectory`.
    ///
    /// - Parameters:
    ///   - bundleIdentifier: The app's bundle identifier.
    ///   - displayName: The name the app shows.
    ///   - version: The app's version, or empty.
    ///   - build: The app's build, or empty.
    ///   - capabilities: The IDs the app serves.
    ///   - protocolVersion: The major version of the protocol the app speaks.
    ///   - lastSeen: When the app last said it serves.
    ///   - storeDirectory: The app's own directory of the group's store.
    public init(
        bundleIdentifier: String,
        displayName: String,
        version: String,
        build: String,
        capabilities: [String],
        protocolVersion: Int,
        lastSeen: Date,
        storeDirectory: URL
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.version = version
        self.build = build
        self.capabilities = capabilities.sorted()
        self.protocolVersion = protocolVersion
        self.lastSeen = lastSeen
        self.storeDirectory = storeDirectory
    }

    /// The app's bundle identifier.
    public var id: String {
        bundleIdentifier
    }

    /// Where the app's `DebugDrawerSocketServer` makes its socket, when it serves one: `drawer.sock`
    /// in the app's directory of the store, as `DebugDrawerAppGroupContainer.socketPath` places it. A production app's
    /// receiver serves no socket, and the sidecar reads the store instead.
    public var socketPath: String {
        storeDirectory.appending(path: "drawer.sock", directoryHint: .notDirectory).path
    }

    /// Whether the app's commands act only within a session the sidecar opens: it serves
    /// `DebugDrawerSessions.pluginID`.
    @MainActor public var requiresSession: Bool {
        capabilities.contains(DebugDrawerSessions.pluginID)
    }

    /// Whether the app serves anything now: `false` while the host has turned its receiver off
    /// (`DebugDrawerReceiver.isAllowed`), when it lists no ID at all.
    public var isServing: Bool {
        !capabilities.isEmpty
    }

    /// Whether the app serves the model `id` names.
    ///
    /// - Parameter id: A capability's or plugin model's ID.
    /// - Returns: `true` when the app lists it.
    public func serves(_ id: String) -> Bool {
        capabilities.contains(id)
    }

    /// The app as its presence file in its directory of the store, `storeDirectory`, describes it.
    init(_ presence: AppPresence, storeDirectory: URL) {
        self.init(
            bundleIdentifier: presence.identity.bundleIdentifier,
            displayName: presence.identity.displayName,
            version: presence.identity.version,
            build: presence.identity.build,
            capabilities: presence.capabilities,
            protocolVersion: presence.hello.version,
            lastSeen: presence.lastSeen,
            storeDirectory: storeDirectory
        )
        servesInSessionsOnly = presence.servesInSessionsOnly == true
    }
}
