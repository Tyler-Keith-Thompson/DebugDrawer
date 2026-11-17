#if DEBUG
    import Foundation

    /// The rules as the plugin saves them: JSON with a format version, so a later format can
    /// read this one and an older build refuses a newer file rather than misread it.
    struct NetworkMockRuleFile: Codable, Equatable {
        /// The format this build writes.
        static let currentVersion = 1

        var version: Int
        var rules: [NetworkMockRule]

        /// Why a saved file couldn't be read.
        enum ReadError: Error, Equatable {
            /// The file isn't JSON in the format.
            case unreadable
            /// The file was written in a format version this build doesn't know.
            case unsupportedVersion(Int)
        }

        /// The file's JSON for `rules`: pretty-printed with sorted keys, so a change shows as a small
        /// diff.
        static func encode(_ rules: [NetworkMockRule]) -> Data {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            // Strings, numbers, Booleans and arrays and dictionaries of them: encoding can't fail.
            return (try? encoder.encode(NetworkMockRuleFile(version: currentVersion, rules: rules))) ?? Data()
        }

        /// The rules in a saved file.
        ///
        /// - Throws: `ReadError.unsupportedVersion` for a file of a later format, and
        ///   `ReadError.unreadable` for one that isn't the format at all.
        static func decode(_ data: Data) throws(ReadError) -> [NetworkMockRule] {
            struct Header: Decodable {
                var version: Int
            }
            let decoder = JSONDecoder()
            guard let header = try? decoder.decode(Header.self, from: data) else { throw .unreadable }
            guard header.version <= currentVersion, header.version >= 1 else { throw .unsupportedVersion(header.version) }
            guard let file = try? decoder.decode(NetworkMockRuleFile.self, from: data) else { throw .unreadable }
            return file.rules
        }
    }
#endif
