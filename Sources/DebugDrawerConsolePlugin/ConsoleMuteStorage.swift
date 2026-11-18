#if DEBUG
    import DebugDrawer
    import Foundation

    /// Where the console's mutes are kept between launches.
    protocol ConsoleMuteStorage: Sendable {
        /// The saved file's contents, or `nil` when nothing was ever saved.
        ///
        /// - Throws: When the file exists and can't be read.
        func readMutes() throws -> Data?
        /// Replaces the saved file with `data`.
        ///
        /// - Throws: When the file can't be written.
        func writeMutes(_ data: Data) throws
    }

    /// The mutes in `muted.json`, in Application Support's folder named after the app, then
    /// `DebugDrawer/Console`, beside the sessions' `DebugDrawer/ConsoleSessions`.
    struct _ConsoleMuteStorage: ConsoleMuteStorage {
        static var defaultDirectory: URL {
            URL.applicationSupportDirectory
                .appending(path: Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName, directoryHint: .isDirectory)
                .appending(path: "DebugDrawer/Console", directoryHint: .isDirectory)
        }

        let directory: URL

        private var file: URL {
            directory.appending(path: "muted.json")
        }

        // Both are the drawer's own work, which Disk I/O leaves out.

        func readMutes() throws -> Data? {
            try DebugDrawerActivity.$isDrawerWork.withValue(true) {
                guard FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) else { return nil }
                return try Data(contentsOf: file)
            }
        }

        func writeMutes(_ data: Data) throws {
            try DebugDrawerActivity.$isDrawerWork.withValue(true) {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try data.write(to: file, options: .atomic)
            }
        }
    }

    /// What went wrong reading or saving the mutes.
    enum ConsoleMuteIssue: Equatable {
        /// The saved file isn't in the format; nothing is muted.
        case unreadable
        /// The saved file is in a later format; nothing is muted.
        case unsupportedVersion(Int)
        /// A change couldn't be saved; it lasts until the app quits.
        case notSaved

        /// The issue in a sentence.
        var message: String {
            switch self {
            case .unreadable: "The saved mutes couldn't be read, so nothing is muted."
            case let .unsupportedVersion(version): "The saved mutes are in format \(version), newer than this build reads, so nothing is muted."
            case .notSaved: "The last change to the mutes couldn't be saved; it lasts until the app quits."
            }
        }
    }
#endif
