#if DEBUG
    import DebugDrawer
    import Foundation

    /// Where the conditioning profiles are kept between launches.
    protocol NetworkConditionStorage: Sendable {
        /// The saved file's contents, or `nil` when nothing was ever saved.
        ///
        /// - Throws: When the file exists and can't be read.
        func readProfiles() throws -> Data?
        /// Replaces the saved file with `data`.
        func writeProfiles(_ data: Data) throws
    }

    /// The profiles in `conditions.json`, beside the mock rules' `rules.json`.
    struct _NetworkConditionStorage: NetworkConditionStorage {
        let directory: URL

        private var file: URL {
            directory.appending(path: "conditions.json")
        }

        // Both are the drawer's own work, which Disk I/O leaves out.

        func readProfiles() throws -> Data? {
            try DebugDrawerActivity.$isDrawerWork.withValue(true) {
                guard FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) else { return nil }
                return try Data(contentsOf: file)
            }
        }

        func writeProfiles(_ data: Data) throws {
            try DebugDrawerActivity.$isDrawerWork.withValue(true) {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try data.write(to: file, options: .atomic)
            }
        }
    }
#endif
