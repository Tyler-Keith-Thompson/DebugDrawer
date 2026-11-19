/// Where a ``DebugDrawerNetworkServer`` listens, and whether it advertises itself over Bonjour.
///
/// ```swift
/// // Listens on every interface and advertises as the device's name (the default).
/// DebugDrawerNetworkServerConfiguration()
/// // Listens on 127.0.0.1 only and advertises nothing: a simulator and a viewer on the same Mac.
/// DebugDrawerNetworkServerConfiguration.loopback
/// ```
public struct DebugDrawerNetworkServerConfiguration: Hashable, Sendable {
    /// The Bonjour service's name, or `nil` for the device's name.
    public var serviceName: String?
    /// The TCP port, or `nil` for one the system picks.
    public var port: UInt16?
    /// Whether the server advertises itself as a ``DebugDrawerBonjourService/type`` service, so a
    /// ``DebugDrawerNetworkBrowser`` finds it.
    public var advertises: Bool
    /// Whether the server listens on the loopback interface (127.0.0.1) only, where nothing off
    /// this device can connect.
    public var loopbackOnly: Bool

    /// A configuration.
    ///
    /// - Parameters:
    ///   - serviceName: The Bonjour service's name, or `nil` for the device's name.
    ///   - port: The TCP port, or `nil` for one the system picks.
    ///   - advertises: Whether to advertise the service over Bonjour.
    ///   - loopbackOnly: Whether to listen on 127.0.0.1 only.
    public init(serviceName: String? = nil, port: UInt16? = nil, advertises: Bool = true, loopbackOnly: Bool = false) {
        self.serviceName = serviceName
        self.port = port
        self.advertises = advertises
        self.loopbackOnly = loopbackOnly
    }

    /// 127.0.0.1 on a port the system picks, advertising nothing: for a viewer on the same Mac
    /// as the app or its simulator.
    public static let loopback = DebugDrawerNetworkServerConfiguration(advertises: false, loopbackOnly: true)
}
