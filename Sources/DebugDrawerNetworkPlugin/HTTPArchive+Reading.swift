#if DEBUG
    import Foundation

    extension HTTPArchive {
        /// Why a file couldn't be read as an HTTP Archive.
        enum ReadError: Error, Equatable, Codable {
            /// The file couldn't be opened.
            case unreadableFile
            /// The file isn't JSON.
            case notJSON
            /// The file is JSON, but has no `log` with `entries`.
            case notAnArchive
            /// The archive is of a format version other than 1.x.
            case unsupportedVersion(String)
            /// The entry at this index, from 0, has no request method or URL, or a value of the
            /// wrong type.
            case invalidEntry(Int)

            /// What went wrong, in a sentence.
            var message: String {
                switch self {
                case .unreadableFile: "The file couldn't be opened."
                case .notJSON: "The file isn't JSON."
                case .notAnArchive: "The file is JSON, but not an HTTP Archive: it has no log of entries."
                case let .unsupportedVersion(version): "The archive is HAR \(version); only HAR 1.1 and 1.2 can be read."
                case let .invalidEntry(index): "Request \(index + 1) in the archive has no method or URL, or a value of the wrong kind."
                }
            }
        }

        /// The archive in `data`: HAR 1.1 or 1.2 JSON, as DebugDrawer, browsers and proxies write it.
        ///
        /// - Throws: `ReadError.notJSON` for data that isn't JSON, `ReadError.notAnArchive` for
        ///   JSON with no log of entries, `ReadError.unsupportedVersion` for a version other than
        ///   1.x, and `ReadError.invalidEntry` for an entry with no request method or URL.
        static func read(_ data: Data) throws(ReadError) -> HTTPArchive {
            guard (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil else { throw .notJSON }
            let decoder = JSONDecoder()
            guard let header = try? decoder.decode(ArchiveHeader.self, from: data) else { throw .notAnArchive }
            // The format says a missing or empty version means 1.1.
            let version = header.log.version ?? ""
            guard version.isEmpty || version.split(separator: ".").first == "1" else { throw .unsupportedVersion(version) }
            do {
                return try decoder.decode(HTTPArchive.self, from: data)
            } catch {
                throw .invalidEntry(Self.entryIndex(of: error) ?? 0)
            }
        }

        /// The index of the entry a decoding error is in, from the path to the bad value.
        private static func entryIndex(of error: any Error) -> Int? {
            let path: [any CodingKey] = switch error as? DecodingError {
            case let .keyNotFound(_, context), let .typeMismatch(_, context), let .valueNotFound(_, context), let .dataCorrupted(context):
                context.codingPath
            default:
                []
            }
            guard let entries = path.firstIndex(where: { $0.stringValue == "entries" }), entries + 1 < path.count else { return nil }
            return path[entries + 1].intValue
        }
    }

    /// An archive's version and whether it has a list of entries, read before the entries are.
    private struct ArchiveHeader: Decodable {
        struct Log: Decodable {
            var version: String?
            var entries: [AnyEntry]
        }

        /// Anything at all, so the header checks only that `entries` is a list.
        struct AnyEntry: Decodable {
            init(from _: any Decoder) {}
        }

        var log: Log
    }
#endif
