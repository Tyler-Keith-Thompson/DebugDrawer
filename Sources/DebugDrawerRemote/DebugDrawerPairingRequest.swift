import Foundation

/// A viewer asking to pair with this device, waiting for the code the device shows.
///
/// The device shows ``code`` with the viewer's name; the person reads it and types it into the
/// viewer. The viewer is paired when it sends this code back, and turned away for good when it
/// sends any other, or when ``DebugDrawerNetworkServer/reject(_:)`` declines it. Each request gets
/// a new code, used once.
public struct DebugDrawerPairingRequest: Identifiable, Hashable, Sendable {
    /// The request's identity, which a ``DebugDrawerPairedViewer`` keeps once it pairs.
    public let id: UUID
    /// The name the viewer gave, such as its Mac's name, at most 64 characters.
    public let viewerName: String
    /// The six digits the viewer must send back, such as `"042917"`.
    public let code: String

    /// A request from `viewerName`, to be answered with `code`.
    ///
    /// - Parameters:
    ///   - id: The request's identity.
    ///   - viewerName: The name the viewer gave.
    ///   - code: The code the viewer must send back.
    public init(id: UUID, viewerName: String, code: String) {
        self.id = id
        self.viewerName = viewerName
        self.code = code
    }
}

/// A viewer paired with this device, which reads and drives the models the server offers.
public struct DebugDrawerPairedViewer: Identifiable, Hashable, Sendable {
    /// The identity its ``DebugDrawerPairingRequest`` had.
    public let id: UUID
    /// The name the viewer gave.
    public let name: String

    /// A viewer named `name`, paired through the request `id`.
    ///
    /// - Parameters:
    ///   - id: The identity of the request it paired through.
    ///   - name: The name the viewer gave.
    public init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }
}
