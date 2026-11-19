/// Why a ``DebugDrawerNetworkTransport`` isn't paired with its device.
///
/// It exists in every build; release builds' transports fail with ``unreachable``.
public enum DebugDrawerPairingError: Error, Equatable, Sendable {
    /// Nothing answered at the device's address: it isn't listening, or can't be reached. Release
    /// builds, which carry nothing, fail with this too.
    case unreachable
    /// The person on the device declined, or the device already shows as many requests as it
    /// allows.
    case rejected
    /// The code sent isn't the one the device showed. The device closes the connection; pair
    /// again with a new transport, and the device shows a new code.
    case wrongCode
    /// The connection closed during pairing, or after it.
    case disconnected
    /// The task waiting for the device's answer was cancelled.
    case cancelled
}
