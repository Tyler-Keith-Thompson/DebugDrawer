import Foundation

// One file of the app-group store: a transport message, with the store's schema version and the
// hello of the build that wrote it. The store has no stream to greet over, and an app and a viewer
// from different releases read each other's files at any time, even with the other not running, so
// each document carries what a hello would: the reader skips a document whose writer it shares no
// protocol version with, and learns the writer's capabilities from one it reads.
//
// The keys sit beside the message's, not around it, so a build that reads a bare message (schema
// 1, which had neither key) still reads every document this one writes. A document is read at its
// own schema and migrated forward one step at a time to the current one (`migrations`); one of a
// newer schema is read for the keys this build knows, as a later schema only adds keys. Nothing is
// rewritten in place: a snapshot file is replaced in the current schema the next time the app
// writes it, and a command file is removed once performed. Rejected: the message nested under a
// key (a schema 1 reader would read no document at all), the schema version in the message's
// `version` (a version 1 receiver drops any message whose format isn't 1), and rewriting old files
// on start (two builds sharing a store would rewrite each other's files back and forth).

/// One document of the app-group store: a message, its schema version, and who wrote it.
package struct StoreDocument: Equatable, Sendable {
    /// The schema this build writes.
    package static let currentSchemaVersion = 2

    /// Each step migrates a document of the schema it is keyed by to the next.
    private static let migrations: [Int: @Sendable (StoreDocument) -> StoreDocument] = [
        // Schema 1 was a bare message, written by a build of protocol version 1.
        1: { document in
            var migrated = document
            migrated.schemaVersion = 2
            migrated.writer = .firstVersion
            return migrated
        }
    ]

    /// The schema the document is in.
    package var schemaVersion = StoreDocument.currentSchemaVersion
    /// The hello of the build that wrote it.
    package var writer = TransportHello.current
    package var message: TransportMessage

    /// A document of the current schema, written by this build.
    package init(_ message: TransportMessage) {
        self.message = message
    }

    /// Whether this build speaks a protocol version its writer does, and so may act on it.
    package var isReadable: Bool {
        TransportHello.current.agreement(with: writer) != nil
    }

    /// The document as JSON, its keys sorted.
    package func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(self)
    }

    /// The document `data` holds, migrated to the current schema, or `nil` when it holds no
    /// message this build reads (malformed, another envelope format, or no writer from schema
    /// 2 on).
    package static func decoded(from data: Data) -> StoreDocument? {
        guard var document = try? JSONDecoder().decode(StoreDocument.self, from: data),
              document.message.version == TransportMessage.currentVersion else { return nil }
        while let migrate = migrations[document.schemaVersion] {
            document = migrate(document)
        }
        return document
    }
}

extension StoreDocument: Codable {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case writer
    }

    package init(from decoder: any Decoder) throws {
        message = try TransportMessage(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        guard schemaVersion >= 1 else {
            throw DecodingError.dataCorruptedError(forKey: .schemaVersion, in: container, debugDescription: "No schema comes before 1")
        }
        // Schema 1 names no writer; its migration fills it in. Every later one must.
        if schemaVersion > 1 {
            writer = try container.decode(TransportHello.self, forKey: .writer)
        }
    }

    package func encode(to encoder: any Encoder) throws {
        try message.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(writer, forKey: .writer)
    }
}
