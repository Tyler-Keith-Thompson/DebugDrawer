import Foundation

// The handshake a viewer and a device speak before any plugin's data moves, framed like core's
// messages on the same connection: the first frames each way are these, and once the device
// accepts, every frame after is a core `TransportMessage`. A message of its own rather than new
// kinds in core's `TransportMessage`: pairing belongs to the network transport alone, and the
// socket and store, which a process reaches only through the app's own container, have nothing to
// pair. Versioned as core's is, so a viewer and a device from different releases refuse each
// other rather than misread.

#if DEBUG
    /// One message of the pairing handshake.
    struct PairingMessage: Codable, Equatable, Sendable {
        /// What a pairing message says.
        enum Kind: String, Codable, Sendable {
            /// Viewer to device: let me view your models; I am `viewerName`.
            case request
            /// Device to viewer: the device shows a code now; send it back.
            case waitingForCode
            /// Viewer to device: the code the person read off the device.
            case code
            /// Device to viewer: paired; core's messages follow.
            case accepted
            /// Device to viewer: not paired, for `rejection`; the device closes the connection.
            case rejected
        }

        /// Why a device refused a viewer.
        enum Rejection: String, Codable, Sendable {
            /// The person on the device turned it down.
            case declined
            /// The code sent isn't the one the device showed.
            case wrongCode
            /// The device already shows as many requests as it allows.
            case busy
        }

        /// The handshake this build speaks; a peer that sends another is closed.
        static let currentVersion = 1

        var version = PairingMessage.currentVersion
        var pairing: Kind
        var viewerName: String?
        var code: String?
        var rejection: Rejection?

        /// The message as JSON, its keys sorted.
        func encoded() -> Data {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            // Every member is a string, an enum of strings or an integer: encoding can't fail.
            return (try? encoder.encode(self)) ?? Data()
        }

        /// The message `data` holds, or `nil` when it holds none this build reads (malformed, or
        /// another version).
        static func decoded(from data: Data) -> PairingMessage? {
            guard let message = try? JSONDecoder().decode(PairingMessage.self, from: data),
                  message.version == currentVersion else { return nil }
            return message
        }
    }
#endif
