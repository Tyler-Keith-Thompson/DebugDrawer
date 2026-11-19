import Foundation
import os

// One connection's view of the side across it, written once for both ends: `RegistrySession` (the
// models' side) and `RemoteModels` (the viewer's) hand it every message they receive before acting
// on one. It keeps the peer's hello, so either end can ask what the two agreed, and it drops a kind
// this build doesn't know, logging each such kind the first time the peer sends it: a newer peer
// that sends one often would otherwise fill the log, and a dropped message breaks nothing, as the
// default-deny receiver acts only on kinds it knows. The kinds logged are capped, so a peer
// inventing names can't grow the set without bound.

#if DEBUG
    /// What a connection knows of its peer: its hello, the agreement with it, and the unknown
    /// kinds it has sent.
    package struct TransportPeer: Sendable {
        private static let logger = Logger(subsystem: "DebugDrawer", category: "TransportPeer")
        /// The most unknown kinds remembered, and so logged, per connection.
        static let maximumIgnoredKinds = 32

        /// What a message is, once admitted.
        package enum Admission: Equatable, Sendable {
            /// A message of a kind this build knows, to act on.
            case deliver(TransportMessage)
            /// The peer said hello, and this is what the two sides use from now on.
            case agreed(TransportAgreement)
            /// The peer said hello, and the two sides share no version: close the connection.
            case incompatible(TransportHello)
            /// Dropped: a kind this build doesn't know, or a hello that didn't decode.
            case ignored
        }

        /// What the peer said in its hello; until it says one, version 1's, which had none.
        private(set) var hello = TransportHello.firstVersion
        /// The kinds this build doesn't know that the peer has sent, each logged when first sent.
        private(set) var ignoredKinds: Set<String> = []

        /// A peer that hasn't said hello yet.
        package init() {}

        /// What this build and the peer use: the version and capabilities both have, or `nil`
        /// when they share no version.
        package var agreement: TransportAgreement? {
            TransportHello.current.agreement(with: hello)
        }

        /// Whether the two sides agreed on `capability`.
        func uses(_ capability: TransportCapability) -> Bool {
            agreement?.capabilities.contains(capability) == true
        }

        /// Takes in a message from the peer: a hello is kept and answered with the agreement, a kind
        /// this build doesn't know is dropped (logged the first time), and anything else is handed
        /// back to act on.
        package mutating func admit(_ message: TransportMessage) -> Admission {
            switch message.kind {
            case .hello:
                guard let hello = try? JSONDecoder().decode(TransportHello.self, from: message.payload) else {
                    Self.logger.notice("Ignored a hello that didn't decode")
                    return .ignored
                }
                self.hello = hello
                guard let agreement else {
                    Self.logger.error("""
                        Closing a connection to a peer of protocol version \(hello.version, privacy: .public) \
                        (back to \(hello.oldestVersion, privacy: .public)): this build speaks \
                        \(TransportHello.current.version, privacy: .public) back to \(TransportHello.current.oldestVersion, privacy: .public)
                        """)
                    return .incompatible(hello)
                }
                return .agreed(agreement)
            case let .unknown(name):
                if ignoredKinds.count < Self.maximumIgnoredKinds, ignoredKinds.insert(name).inserted {
                    let kind = String(name.prefix(64))
                    Self.logger.notice("Ignored a message of kind \(kind, privacy: .public), which this build doesn't know; later ones go unlogged")
                }
                return .ignored
            case .subscribe, .unsubscribe, .snapshot, .command, .acknowledgement:
                return .deliver(message)
            }
        }
    }
#endif
