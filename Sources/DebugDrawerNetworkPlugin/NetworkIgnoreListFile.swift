#if DEBUG
    import DebugDrawerNetwork
    import Foundation

    /// The ignore list as the plugin saves it, in `ignored.json`: JSON with a format version, so a
    /// later format can read this one and an older build refuses a newer file rather than misread
    /// it.
    ///
    /// A copy of `NetworkMockRuleFile`'s shape for another list, as `NetworkConditionProfileFile`
    /// is: a generic file over the three would tie formats that version apart.
    struct NetworkIgnoreListFile: Codable, Equatable {
        /// The format this build writes.
        static let currentVersion = 1

        var version: Int
        var domains: [String]

        /// The file's JSON for `domains`, pretty-printed, so a change shows as a small diff.
        static func encode(_ domains: [NetworkIgnoredDomain]) -> Data {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            // An integer and an array of strings: encoding can't fail.
            return (try? encoder.encode(NetworkIgnoreListFile(version: currentVersion, domains: domains.map(\.name)))) ?? Data()
        }

        /// The domains in a saved file, in order, without any that isn't a host (a hand edit's
        /// typo), so one bad line doesn't cost the rest.
        ///
        /// - Throws: `NetworkMockRuleFile.ReadError.unsupportedVersion` for a file of a later
        ///   format, and `.unreadable` for one that isn't the format at all.
        static func decode(_ data: Data) throws(NetworkMockRuleFile.ReadError) -> [NetworkIgnoredDomain] {
            struct Header: Decodable {
                var version: Int
            }
            let decoder = JSONDecoder()
            guard let header = try? decoder.decode(Header.self, from: data) else { throw .unreadable }
            guard header.version <= currentVersion, header.version >= 1 else { throw .unsupportedVersion(header.version) }
            guard let file = try? decoder.decode(NetworkIgnoreListFile.self, from: data) else { throw .unreadable }
            return file.domains.compactMap { try? NetworkIgnoredDomain(parsing: $0) }
        }
    }
#endif
