#if DEBUG
    import Foundation

    /// The profiles as the plugin saves them: JSON with a format version, so a later format can
    /// read this one and an older build refuses a newer file rather than misread it.
    ///
    /// A copy of `NetworkMockRuleFile`'s shape for another list: a generic file over both would
    /// save a dozen lines and tie two formats that version apart.
    struct NetworkConditionProfileFile: Codable, Equatable {
        /// The format this build writes.
        static let currentVersion = 1

        var version: Int
        var profiles: [NetworkConditionProfile]

        /// The file's JSON for `profiles`: pretty-printed with sorted keys, so a change shows as a
        /// small diff.
        static func encode(_ profiles: [NetworkConditionProfile]) -> Data {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            // Strings, numbers, Booleans and arrays of them: encoding can't fail.
            return (try? encoder.encode(NetworkConditionProfileFile(version: currentVersion, profiles: profiles))) ?? Data()
        }

        /// The profiles in a saved file.
        ///
        /// - Throws: `NetworkMockRuleFile.ReadError.unsupportedVersion` for a file of a later
        ///   format, and `.unreadable` for one that isn't the format at all.
        static func decode(_ data: Data) throws(NetworkMockRuleFile.ReadError) -> [NetworkConditionProfile] {
            struct Header: Decodable {
                var version: Int
            }
            let decoder = JSONDecoder()
            guard let header = try? decoder.decode(Header.self, from: data) else { throw .unreadable }
            guard header.version <= currentVersion, header.version >= 1 else { throw .unsupportedVersion(header.version) }
            guard let file = try? decoder.decode(NetworkConditionProfileFile.self, from: data) else { throw .unreadable }
            return file.profiles
        }
    }
#endif
