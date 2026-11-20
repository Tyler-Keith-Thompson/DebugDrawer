import DebugDrawer
import Foundation

/// An app in the group that serves a sidecar, as its presence file in the store describes it: a
/// production app's `DebugDrawerReceiver`, or a debug build's `DebugDrawerAppGroupStoreServer`.
///
/// It holds nothing secret: who the app is, what it serves and when it last said so. A
/// ``DebugDrawerSidecarAppList`` lists one for each app serving the store.
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
    /// When the app last said it serves: as it started, as what it serves changed, or as it came
    /// to the foreground. An app that was killed keeps the time it was last seen.
    public let lastSeen: Date
    /// The store's directory, where the app keeps its snapshots and takes commands.
    public let storeDirectory: URL

    /// An app serving the store in `storeDirectory`.
    ///
    /// - Parameters:
    ///   - bundleIdentifier: The app's bundle identifier.
    ///   - displayName: The name the app shows.
    ///   - version: The app's version, or empty.
    ///   - build: The app's build, or empty.
    ///   - capabilities: The IDs the app serves.
    ///   - lastSeen: When the app last said it serves.
    ///   - storeDirectory: The store's directory.
    public init(
        bundleIdentifier: String,
        displayName: String,
        version: String,
        build: String,
        capabilities: [String],
        lastSeen: Date,
        storeDirectory: URL
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.version = version
        self.build = build
        self.capabilities = capabilities.sorted()
        self.lastSeen = lastSeen
        self.storeDirectory = storeDirectory
    }

    /// The app's bundle identifier.
    public var id: String {
        bundleIdentifier
    }

    /// Where the app's `DebugDrawerSocketServer` makes its socket, when it serves one: `drawer.sock`
    /// in the store's directory, as `DebugDrawerAppGroupContainer` places it. A production app's
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

    /// The app as its presence file in the store in `storeDirectory` describes it.
    init(_ presence: AppPresence, storeDirectory: URL) {
        self.init(
            bundleIdentifier: presence.identity.bundleIdentifier,
            displayName: presence.identity.displayName,
            version: presence.identity.version,
            build: presence.identity.build,
            capabilities: presence.capabilities,
            lastSeen: presence.lastSeen,
            storeDirectory: storeDirectory
        )
    }
}
