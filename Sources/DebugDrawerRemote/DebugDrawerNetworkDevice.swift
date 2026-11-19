import Network

/// An app a ``DebugDrawerNetworkBrowser`` found advertising its models on the local network.
public struct DebugDrawerNetworkDevice: Identifiable, Hashable, Sendable {
    /// The Bonjour service's name: the device's name, or the one its server was configured with.
    public let name: String
    /// The app's name, when it advertised one.
    public let appName: String?
    /// The app's bundle identifier, when it advertised one.
    public let bundleIdentifier: String?
    /// The platform the app runs on (`iOS`, `macOS`, …), when it advertised one.
    public let platform: String?
    /// Where to connect: hand it to ``DebugDrawerNetworkTransport/init(endpoint:viewerName:)``.
    public let endpoint: NWEndpoint

    /// The device's identity: its endpoint.
    public var id: NWEndpoint {
        endpoint
    }

    /// A device advertised as `name` at `endpoint`.
    ///
    /// - Parameters:
    ///   - name: The service's name.
    ///   - appName: The app's name.
    ///   - bundleIdentifier: The app's bundle identifier.
    ///   - platform: The app's platform.
    ///   - endpoint: Where to connect.
    public init(name: String, appName: String?, bundleIdentifier: String?, platform: String?, endpoint: NWEndpoint) {
        self.name = name
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.platform = platform
        self.endpoint = endpoint
    }
}
