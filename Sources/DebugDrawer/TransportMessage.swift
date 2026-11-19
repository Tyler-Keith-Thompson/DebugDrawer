import Foundation

// The wire format every transport that leaves the process speaks: the socket's stream, the
// app-group store's files, and `DebugDrawerRemote`'s network transport, which reuses this file and
// `TransportFrameDecoder` unchanged (hence `package`). A message is a JSON object naming its plugin, carrying the
// plugin's own snapshot or command as JSON bytes, so the envelope never needs the plugin's types:
// the side that knows them decodes the payload. JSON over a binary property list or a hand-made
// layout: a person can read it in a capture, and every Apple platform and a non-Apple viewer can
// write it. Rejected: one Codable enum of every plugin's messages (core would name every plugin),
// and the payload nested as a JSON value rather than bytes (the envelope would have to decode
// payloads it can't type).

#if DEBUG
    /// One message between the process holding plugin models and a viewer of them.
    package struct TransportMessage: Codable, Equatable, Sendable {
        /// What a message asks or carries.
        package enum Kind: String, Codable, Sendable {
            /// Viewer to models: send this plugin's snapshots, the current one first.
            case subscribe
            /// Models to viewer: the plugin's state now, its `Snapshot` as JSON.
            case snapshot
            /// Viewer to models: do this, the plugin's `Command` as JSON.
            case command
        }

        /// The format this build writes. A receiver drops a message of another version, so a
        /// viewer and an app built from different releases ignore each other rather than misread.
        static let currentVersion = 1

        var version = TransportMessage.currentVersion
        package var kind: Kind
        /// The plugin's ``DebugDrawerPlugin/id``, or whatever ID its model was registered under.
        package var pluginID: String
        /// The plugin's snapshot or command, encoded as JSON; empty for ``Kind/subscribe``.
        var payload = Data()

        /// The message as JSON, its keys sorted, so the same message is always the same bytes.
        func encoded() throws -> Data {
            try TransportMessage.encoder.encode(self)
        }

        /// The message `data` holds, or `nil` when it holds none this build reads (malformed, or
        /// another version).
        package static func decoded(from data: Data) -> TransportMessage? {
            guard let message = try? JSONDecoder().decode(TransportMessage.self, from: data),
                  message.version == currentVersion else { return nil }
            return message
        }

        /// Encodes a payload, its keys sorted, so a snapshot that didn't change encodes to the
        /// bytes it did before, and a sender can skip it.
        static func payload(_ value: some Encodable) throws -> Data {
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
#endif
