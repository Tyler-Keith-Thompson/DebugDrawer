import Foundation

// Where an app and its sidecar meet: the app group's shared container, resolved the one way both
// sides must agree on, and the socket and store paths in it. The resolution is
// `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)` whether or not the app is
// sandboxed: on macOS it gives `~/Library/Group Containers/<group>` to a sandboxed app and to one
// outside the sandbox alike, so a non-sandboxed host and a sandboxed sidecar find the same
// directory. It returns nil only where the system checks the entitlement first (iOS, visionOS,
// tvOS, watchOS), which throws `noAppGroupContainer` rather than trapping on a force unwrap or
// falling back to a directory the group doesn't protect. Access isn't checked here: the servers
// and transports check it as they first touch their directories, which is where macOS asks the
// person, and throw `accessDenied` there.
//
// The socket sits beside the store, in `DebugDrawer/`, rather than at the container's root, so the
// sidecar's watch on the socket's directory hears the socket and the store's own directories, not
// whatever else the app keeps in the container. The resolver is a closure with the system's as its
// default, the seam the charter asks for, so a test can give a container that is missing.
//
// Rejected: a `DebugDrawerSidecarTransport(appGroup:)` and server initializers taking the group
// (four stand-ins for what one value gives every transport), and checking access at resolution
// (the prompt belongs to the first file call, and a check here would ask twice).

#if DEBUG
    /// An app group's shared container, and where the socket and store transports keep their files
    /// in it.
    ///
    /// ```swift
    /// let group = try DebugDrawerAppGroupContainer(groupIdentifier: "TEAMID.com.example.debug")
    /// let server = DebugDrawerSocketServer(registry: registry, socketPath: group.socketPath)
    /// ```
    ///
    /// The app and its sidecar resolve the same container this way whether either is sandboxed or
    /// not. Release builds get a stand-in whose initializer throws
    /// ``DebugDrawerTransportError/unreachable``.
    public struct DebugDrawerAppGroupContainer: Equatable, Sendable {
        /// The app group's identifier.
        public let groupIdentifier: String
        /// The group's shared container.
        public let url: URL

        /// The container of `groupIdentifier`, as `containerURL` resolves it.
        ///
        /// - Parameters:
        ///   - groupIdentifier: The app group both apps list in their
        ///     `com.apple.security.application-groups` entitlement.
        ///   - containerURL: Resolves a group's container; the system's
        ///     `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)` by default.
        /// - Throws: ``DebugDrawerTransportError/noAppGroupContainer`` when it resolves none.
        public init(
            groupIdentifier: String,
            containerURL: (String) -> URL? = { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
        ) throws(DebugDrawerTransportError) {
            guard let url = containerURL(groupIdentifier) else { throw .noAppGroupContainer }
            self.groupIdentifier = groupIdentifier
            self.url = url
        }

        /// Where the app's ``DebugDrawerSocketServer`` makes its socket: `DebugDrawer/drawer.sock`
        /// in the container.
        public var socketPath: String {
            storeDirectory.appending(path: "drawer.sock", directoryHint: .notDirectory).path
        }

        /// The directory of the app's ``DebugDrawerAppGroupStoreServer``: `DebugDrawer` in the
        /// container.
        public var storeDirectory: URL {
            url.appending(path: "DebugDrawer", directoryHint: .isDirectory)
        }
    }
#else
    // The release stand-in: the same members, resolving nothing.

    /// Release builds resolve no container: this stand-in's initializer throws
    /// ``DebugDrawerTransportError/unreachable``.
    public struct DebugDrawerAppGroupContainer: Equatable, Sendable {
        /// Never set: the initializer throws.
        public let groupIdentifier: String
        /// Never set: the initializer throws.
        public let url: URL

        /// Throws ``DebugDrawerTransportError/unreachable``.
        ///
        /// - Parameters:
        ///   - groupIdentifier: Ignored.
        ///   - containerURL: Never called.
        /// - Throws: ``DebugDrawerTransportError/unreachable``, always.
        public init(
            groupIdentifier: String,
            containerURL: (String) -> URL? = { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
        ) throws(DebugDrawerTransportError) {
            throw .unreachable
        }

        /// Where the socket would be.
        public var socketPath: String {
            storeDirectory.appending(path: "drawer.sock", directoryHint: .notDirectory).path
        }

        /// Where the store would be.
        public var storeDirectory: URL {
            url.appending(path: "DebugDrawer", directoryHint: .isDirectory)
        }
    }
#endif
