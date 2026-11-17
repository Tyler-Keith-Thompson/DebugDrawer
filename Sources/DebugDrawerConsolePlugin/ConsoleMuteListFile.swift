#if DEBUG
    import Foundation

    /// The mutes as the plugin saves them, in `muted.json`: JSON with a format version, so a later
    /// format can read this one and an older build refuses a newer file rather than misread it.
    ///
    /// A copy of the Network plugin's ignore-list file shape for another list: the plugins share
    /// no code, and a dozen lines cost less than a module both would depend on.
    struct ConsoleMuteListFile: Codable, Equatable {
        /// The format this build writes.
        static let currentVersion = 1

        /// One mute: a subsystem, and a category of it when only that category is muted.
        struct Entry: Codable, Equatable {
            var subsystem: String
            var category: String?
        }

        /// Why a saved file couldn't be read.
        enum ReadError: Error, Equatable {
            /// The file isn't JSON in the format.
            case unreadable
            /// The file was written in a format version this build doesn't know.
            case unsupportedVersion(Int)
        }

        var version: Int
        var mutes: [Entry]

        /// The file's JSON for `mutes`, pretty-printed with sorted keys, so a change shows as a
        /// small diff.
        static func encode(_ mutes: [ConsoleMute]) -> Data {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let entries = mutes.map { mute in
                switch mute {
                case let .subsystem(subsystem): Entry(subsystem: subsystem)
                case let .category(category, subsystem): Entry(subsystem: subsystem, category: category)
                }
            }
            // An integer and an array of strings: encoding can't fail.
            return (try? encoder.encode(ConsoleMuteListFile(version: currentVersion, mutes: entries))) ?? Data()
        }

        /// The mutes in a saved file, in order, without any whose subsystem is empty (a hand
        /// edit's slip), so one bad entry doesn't cost the rest.
        ///
        /// - Throws: `ReadError.unsupportedVersion` for a file of a later format, and
        ///   `.unreadable` for one that isn't the format at all.
        static func decode(_ data: Data) throws(ReadError) -> [ConsoleMute] {
            struct Header: Decodable {
                var version: Int
            }
            let decoder = JSONDecoder()
            guard let header = try? decoder.decode(Header.self, from: data) else { throw .unreadable }
            guard header.version <= currentVersion, header.version >= 1 else { throw .unsupportedVersion(header.version) }
            guard let file = try? decoder.decode(ConsoleMuteListFile.self, from: data) else { throw .unreadable }
            return file.mutes.compactMap { entry in
                guard !entry.subsystem.isEmpty else { return nil }
                guard let category = entry.category, !category.isEmpty else { return .subsystem(entry.subsystem) }
                return .category(category, subsystem: entry.subsystem)
            }
        }
    }
#endif
