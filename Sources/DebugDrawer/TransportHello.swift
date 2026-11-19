import Foundation

// What each side of a stream says first, so builds from different releases can pair: the app and a
// sidecar ship on different schedules. Each side sends its hello as it connects, without waiting
// for the other's, and both work out the same agreement from the two: the lower of the two
// versions, if each side still speaks it, and the capabilities both list. A side never sends what
// the agreement leaves out, and a peer it can't agree with is closed, its connects failing with
// `incompatibleVersion`.
//
// The version is a major version alone. What a release adds without breaking anyone is a
// capability, named by what it lets a side do, so a peer learns of it by name and a minor version
// would say nothing more. Each release speaks its own version and the one before
// (`oldestVersion`), so a peer one major version ahead or behind connects, and one two apart fails
// clearly. A peer that never says hello speaks version 1, the protocol's first, which had no hello
// and took commands; it drops a hello as a kind it doesn't know, so it pairs with this one as it
// is.
//
// Rejected: a semantic version with a minor (capabilities name what a minor would number, feature
// by feature); the newer side alone deciding (both sides must agree without another round trip, so
// the rule is symmetric); refusing any other version (the app and the sidecar would have to ship
// together); a hello the viewer must wait for before subscribing (a version 1 app never sends
// one, and the stream is ordered, so a newer app's hello arrives before any snapshot anyway).

#if DEBUG
    /// A feature a side of a connection has, by name. A feature is used only when both sides list
    /// it; a name this build doesn't know is kept and never matches.
    package struct TransportCapability: RawRepresentable, Codable, Hashable, Sendable {
        package let rawValue: String

        package init(rawValue: String) {
            self.rawValue = rawValue
        }

        package init(from decoder: any Decoder) throws {
            try self.init(rawValue: decoder.singleValueContainer().decode(String.self))
        }

        package func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }

        /// The viewer sends commands, and the models' side performs them. Version 1 has it.
        static let commands = TransportCapability(rawValue: "commands")
        /// The viewer says when it no longer shows a plugin, and the models' side stops sending
        /// that plugin's snapshots. Since version 2.
        static let unsubscribe = TransportCapability(rawValue: "unsubscribe")
    }

    /// What a side of a connection speaks: the protocol's major version, the oldest it still
    /// speaks, and its capabilities.
    package struct TransportHello: Codable, Equatable, Sendable {
        /// The protocol's major version this side speaks.
        var version: Int
        /// The oldest major version this side still speaks.
        var oldestVersion: Int
        /// What this side can do, in a fixed order, so a hello is always the same bytes.
        var capabilities: [TransportCapability]

        /// What this build speaks: version 2, back to version 1.
        package static let current = TransportHello(version: 2, oldestVersion: 1, capabilities: [.commands, .unsubscribe])

        /// What a peer that never says hello speaks: the protocol's first version, which had no
        /// hello and took commands.
        static let firstVersion = TransportHello(version: 1, oldestVersion: 1, capabilities: [.commands])

        /// What this side and `peer` can use together: the lower of their versions and the
        /// capabilities both list, or `nil` when either no longer speaks the other's version.
        ///
        /// The rule is symmetric, so both sides reach the same agreement from the two hellos.
        package func agreement(with peer: TransportHello) -> TransportAgreement? {
            let version = min(self.version, peer.version)
            guard version >= max(oldestVersion, peer.oldestVersion) else { return nil }
            return TransportAgreement(version: version, capabilities: Set(capabilities).intersection(peer.capabilities))
        }
    }

    /// What two sides of a connection agreed on: the version they speak and the capabilities they
    /// use.
    package struct TransportAgreement: Equatable, Sendable {
        /// The protocol's major version both speak.
        var version: Int
        /// The capabilities both have; nothing else is sent.
        var capabilities: Set<TransportCapability>
    }
#endif
