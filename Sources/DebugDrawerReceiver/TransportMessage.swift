import Foundation

// The wire format every transport that leaves the process speaks: the socket's stream, the
// app-group store's files, and `DebugDrawerRemote`'s network transport, which reuses this file and
// `TransportFrameDecoder` unchanged (hence `package`). It lives in the receiver's module, built in
// every configuration, because the release-build `DebugDrawerReceiver` reads and writes the same
// store files as the drawer's debug-build servers and sidecars; the drawer imports it from here.
// A message is a JSON object naming its plugin, carrying the
// plugin's own snapshot or command as JSON bytes, so the envelope never needs the plugin's types:
// the side that knows them decodes the payload. JSON over a binary property list or a hand-made
// layout: a person can read it in a capture, and every Apple platform and a non-Apple viewer can
// write it. Rejected: one Codable enum of every plugin's messages (core would name every plugin),
// and the payload nested as a JSON value rather than bytes (the envelope would have to decode
// payloads it can't type).
//
// Two versions, kept apart on purpose. `version` is the envelope's format: where the kind, plugin
// and payload are. Every protocol version so far writes format 1, so a version 1 build, which
// drops any other format, still reads what a newer one sends.
// The protocol's version, what each side speaks and which features it has, travels in the `hello`
// each side sends as it connects (`TransportHello`). A kind this build doesn't know decodes as
// `unknown`, so a newer peer's message reaches the receiver, which drops and logs it
// (`TransportPeer`), rather than failing to decode where nothing would notice.
//
// A command carries a `commandID` beside its payload, which its acknowledgement names back, so a
// command is performed once however many ways it arrives. It is a key of the envelope, left out
// when absent, rather than inside the payload: the payload is the plugin's own command, which the
// envelope never reads, and an older build ignores a key it doesn't know.

/// One message between the process holding plugin models and a viewer of them.
package struct TransportMessage: Codable, Equatable, Sendable {
    /// What a message asks or carries.
    package enum Kind: Codable, Equatable, Sendable {
        /// Either side, first on a stream: the protocol version and capabilities it speaks,
        /// its ``TransportHello`` as JSON.
        case hello
        /// Viewer to models: send this plugin's snapshots, the current one first.
        case subscribe
        /// Viewer to models: stop sending this plugin's snapshots, sent only to a peer with
        /// ``TransportCapability/unsubscribe``.
        case unsubscribe
        /// Models to viewer: the plugin's state now, its `Snapshot` as JSON.
        case snapshot
        /// Viewer to models: do this, the plugin's `Command` as JSON, under its
        /// ``TransportMessage/commandID``.
        case command
        /// Models to viewer: the command ``TransportMessage/commandID`` names was performed (or
        /// dropped, as no model took it), sent only to a peer with
        /// ``TransportCapability/acknowledgements``.
        case acknowledgement
        /// A kind this build doesn't know, by its name: a newer peer's. Receivers drop it.
        case unknown(String)

        /// The kind its name on the wire names.
        package init(name: String) {
            switch name {
            case "hello": self = .hello
            case "subscribe": self = .subscribe
            case "unsubscribe": self = .unsubscribe
            case "snapshot": self = .snapshot
            case "command": self = .command
            case "acknowledgement": self = .acknowledgement
            default: self = .unknown(name)
            }
        }

        /// The kind's name on the wire.
        package var name: String {
            switch self {
            case .hello: "hello"
            case .subscribe: "subscribe"
            case .unsubscribe: "unsubscribe"
            case .snapshot: "snapshot"
            case .command: "command"
            case .acknowledgement: "acknowledgement"
            case let .unknown(name): name
            }
        }

        package init(from decoder: any Decoder) throws {
            try self.init(name: decoder.singleValueContainer().decode(String.self))
        }

        package func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(name)
        }
    }

    /// The envelope's format this build writes. A receiver drops a message of another format,
    /// as it can't know where the kind and plugin are; the protocol's version is the hello's.
    package static let currentVersion = 1

    package var version = TransportMessage.currentVersion
    package var kind: Kind
    /// The plugin's `DebugDrawerPlugin.id`, or whatever ID its model was registered under;
    /// empty for ``Kind/hello``.
    package var pluginID: String
    /// The plugin's snapshot or command, or the hello, encoded as JSON; empty for
    /// ``Kind/subscribe`` and ``Kind/unsubscribe``.
    package var payload = Data()
    /// What names a command, so its ``Kind/acknowledgement`` can name it back and the models'
    /// side performs it once however many ways it arrives; `nil` for every other kind, and
    /// left out of the JSON then.
    package var commandID: UUID?

    /// A message of the current envelope format.
    package init(kind: Kind, pluginID: String, payload: Data = Data(), commandID: UUID? = nil) {
        self.kind = kind
        self.pluginID = pluginID
        self.payload = payload
        self.commandID = commandID
    }

    /// A hello saying `hello`.
    package static func hello(_ hello: TransportHello) -> TransportMessage {
        // A hello holds integers and strings only, so encoding it can't fail.
        TransportMessage(kind: .hello, pluginID: "", payload: (try? payload(hello)) ?? Data())
    }

    /// The message as JSON, its keys sorted, so the same message is always the same bytes.
    package func encoded() throws -> Data {
        try TransportMessage.encoder.encode(self)
    }

    /// The message `data` holds, or `nil` when it holds none this build reads (malformed, or
    /// another envelope format). A kind this build doesn't know reads as
    /// ``Kind/unknown(_:)``.
    package static func decoded(from data: Data) -> TransportMessage? {
        guard let message = try? JSONDecoder().decode(TransportMessage.self, from: data),
              message.version == currentVersion else { return nil }
        return message
    }

    /// Encodes a payload, its keys sorted, so a snapshot that didn't change encodes to the
    /// bytes it did before, and a sender can skip it.
    package static func payload(_ value: some Encodable) throws -> Data {
        try encoder.encode(value)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return encoder
    }
}

/// Frames for a byte stream: each message is a 4-byte big-endian length, then that many bytes
/// of ``TransportMessage`` JSON.
package enum TransportFraming {
    /// The longest frame a reader accepts: 64 MiB. A longer length means the stream is not
    /// this format, or is corrupt, and the reader closes it.
    package static let maximumLength = 64 << 20

    /// `message` as one frame.
    package static func frame(_ message: TransportMessage) throws -> Data {
        try frame(body: message.encoded())
    }

    /// `body`, any bytes up to ``maximumLength``, as one frame: what a transport that speaks
    /// a message of its own on the same stream (the network transport's pairing) sends.
    package static func frame(body: Data) -> Data {
        var length = UInt32(body.count).bigEndian
        var frame = Data(bytes: &length, count: MemoryLayout<UInt32>.size)
        frame.append(body)
        return frame
    }
}

/// Splits a byte stream into frames as its bytes arrive, however the stream cuts them.
package struct TransportFrameDecoder {
    /// The stream announced a frame longer than ``TransportFraming/maximumLength``.
    package struct FrameTooLong: Error {}

    private var buffer = Data()

    /// A decoder that has read nothing yet.
    package init() {}

    /// Adds `bytes` and returns the bodies of the frames they complete, in order. Bytes of an
    /// unfinished frame wait for the next call.
    ///
    /// - Throws: ``FrameTooLong`` when a frame announces more than
    ///   ``TransportFraming/maximumLength`` bytes; the stream can't be read on from there.
    package mutating func append(_ bytes: Data) throws(FrameTooLong) -> [Data] {
        buffer.append(bytes)
        var bodies: [Data] = []
        let headerLength = MemoryLayout<UInt32>.size
        while buffer.count >= headerLength {
            let length = buffer.prefix(headerLength).reduce(0) { $0 << 8 | Int($1) }
            guard length <= TransportFraming.maximumLength else { throw FrameTooLong() }
            guard buffer.count >= headerLength + length else { break }
            let start = buffer.startIndex + headerLength
            bodies.append(Data(buffer[start ..< start + length]))
            buffer = Data(buffer[(start + length)...])
        }
        return bodies
    }
}
