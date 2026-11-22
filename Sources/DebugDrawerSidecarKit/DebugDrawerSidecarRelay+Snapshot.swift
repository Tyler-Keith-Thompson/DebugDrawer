#if canImport(DebugDrawerRemote)
    import Foundation

    // What a Mac viewer reads of the relay itself, under its own ID: which app it reaches, whether
    // a session is open there and until when, and the plugin IDs it relays now, so a viewer knows
    // what to connect to and shows the plugins going as the session ends. Values, real in every
    // build, so a viewer decodes them unchanged in release. It names the session's expiry and
    // nothing of its grant: the person holding the grant is the sidecar's, and the viewer needs
    // only when the relay stops.

    extension DebugDrawerSidecarRelay {
        /// What a paired viewer reads of the relay, under ``DebugDrawerSidecarRelay/pluginID``.
        ///
        /// A viewer connects with `command: Never.self`: the relay takes no command, as opening and
        /// ending a session is for the person holding the sidecar.
        public struct Snapshot: Codable, Equatable, Sendable {
            /// The bundle identifier of the app the relay reaches.
            public var bundleIdentifier: String
            /// The app's name.
            public var displayName: String
            /// The app's version.
            public var version: String
            /// The app's build.
            public var build: String
            /// When the open session expires, while the relay forwards within it; `nil` while it
            /// forwards nothing.
            public var sessionExpires: Date?
            /// The plugin IDs the relay serves now, sorted: those of the app's capabilities the
            /// open session may read whose first snapshot has arrived. Empty outside a session.
            public var pluginIDs: [String]

            /// A snapshot of the relay.
            ///
            /// - Parameters:
            ///   - bundleIdentifier: The app's bundle identifier.
            ///   - displayName: The app's name.
            ///   - version: The app's version.
            ///   - build: The app's build.
            ///   - sessionExpires: When the session the relay forwards within expires; `nil`
            ///     outside one.
            ///   - pluginIDs: The plugin IDs relayed now.
            public init(
                bundleIdentifier: String,
                displayName: String,
                version: String,
                build: String,
                sessionExpires: Date? = nil,
                pluginIDs: [String] = []
            ) {
                self.bundleIdentifier = bundleIdentifier
                self.displayName = displayName
                self.version = version
                self.build = build
                self.sessionExpires = sessionExpires
                self.pluginIDs = pluginIDs.sorted()
            }

            /// Whether the relay forwards now: a session is open on the device.
            public var isRelaying: Bool {
                sessionExpires != nil
            }
        }
    }
#endif
