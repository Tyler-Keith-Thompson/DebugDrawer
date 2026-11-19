#if DEBUG
    import DebugDrawer
    import Foundation

    /// Where the mock rules and their body files are kept between launches.
    protocol NetworkMockStorage: Sendable {
        /// The saved file's contents, or `nil` when nothing was ever saved.
        ///
        /// - Throws: When the file exists and can't be read.
        func readRules() throws -> Data?
        /// Replaces the saved file with `data`.
        func writeRules(_ data: Data) throws
        /// Keeps `data` as a body file and returns its name; `fileExtension` (without the dot) keeps
        /// its type, `nil` for none.
        func addBody(_ data: Data, fileExtension: String?) throws -> String
        /// Keeps `data` as the body file named `name`, replacing one of that name.
        func writeBody(_ data: Data, named name: String) throws
        /// The body file named `name`, or `nil` when there is none.
        func body(named name: String) -> Data?
        /// Removes the body file named `name`, if there is one.
        func removeBody(named name: String)
    }

    /// The rules in `rules.json` and the bodies in `Bodies/`, in a directory the app owns.
    struct _NetworkMockStorage: NetworkMockStorage {
        /// Application Support's folder named after the app, as on macOS Application Support is
        /// shared by every app that isn't sandboxed, then `DebugDrawer/NetworkMocks`.
        static var defaultDirectory: URL {
            URL.applicationSupportDirectory
                .appending(path: Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName, directoryHint: .isDirectory)
                .appending(path: "DebugDrawer/NetworkMocks", directoryHint: .isDirectory)
        }

        let directory: URL

        private var rulesFile: URL {
            directory.appending(path: "rules.json")
        }

        private var bodies: URL {
            directory.appending(path: "Bodies", directoryHint: .isDirectory)
        }

        // Every call is the drawer's own work, which Disk I/O leaves out.

        func readRules() throws -> Data? {
            try DebugDrawerActivity.$isDrawerWork.withValue(true) {
                guard FileManager.default.fileExists(atPath: rulesFile.path(percentEncoded: false)) else { return nil }
                return try Data(contentsOf: rulesFile)
            }
        }

        func writeRules(_ data: Data) throws {
            try DebugDrawerActivity.$isDrawerWork.withValue(true) {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try data.write(to: rulesFile, options: .atomic)
            }
        }

        func addBody(_ data: Data, fileExtension: String?) throws -> String {
            let upload = NetworkMockBodyUpload(data: data, fileExtension: fileExtension)
            try writeBody(upload.data, named: upload.name)
            return upload.name
        }

        func writeBody(_ data: Data, named name: String) throws {
            try DebugDrawerActivity.$isDrawerWork.withValue(true) {
                try FileManager.default.createDirectory(at: bodies, withIntermediateDirectories: true)
                try data.write(to: bodies.appending(path: name), options: .atomic)
            }
        }

        func body(named name: String) -> Data? {
            DebugDrawerActivity.$isDrawerWork.withValue(true) {
                try? Data(contentsOf: bodies.appending(path: name))
            }
        }

        func removeBody(named name: String) {
            DebugDrawerActivity.$isDrawerWork.withValue(true) {
                try? FileManager.default.removeItem(at: bodies.appending(path: name))
            }
        }
    }
#endif
