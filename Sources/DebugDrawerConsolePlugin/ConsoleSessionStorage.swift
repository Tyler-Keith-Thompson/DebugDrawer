#if DEBUG
    import Foundation

    /// Where the Console plugin keeps the log lines of each launch, so the next launch can show
    /// them: a file of bytes per session, which the plugin only ever appends to, lists, reads
    /// whole and deletes.
    ///
    /// The default keeps each session as a file in Application Support. Pass another conformer to
    /// `installConsole(sessions:)` through ``ConsoleSessionPersistence`` to keep them elsewhere.
    /// The plugin calls it from one serial queue at a time for writes, and from the main actor to
    /// read the newest earlier session into a bug report, so a conformer must be safe to call
    /// from both.
    public protocol ConsoleSessionStorage: Sendable {
        /// Every session kept, in any order.
        ///
        /// - Throws: When the sessions can't be listed.
        func sessionFiles() throws -> [ConsoleSessionFile]
        /// Appends `data` to the end of the session named `name`, which is created when it doesn't
        /// exist.
        ///
        /// - Throws: When the data can't be written.
        func append(_ data: Data, toSessionNamed name: String) throws
        /// The whole of the session named `name`.
        ///
        /// - Throws: When there is no such session, or it can't be read.
        func contents(ofSessionNamed name: String) throws -> Data
        /// Deletes the session named `name`; one already gone is no failure.
        ///
        /// - Throws: When it exists and can't be deleted.
        func deleteSession(named name: String) throws
    }

    /// A session a ``ConsoleSessionStorage`` keeps: its name and how many bytes it holds.
    public struct ConsoleSessionFile: Hashable, Sendable {
        /// The name the plugin gave it: its start, then a unique id, as `<start>-<UUID>.jsonl`, so
        /// names sort in the order the sessions started.
        public var name: String
        /// How many bytes it holds.
        public var byteCount: Int

        public init(name: String, byteCount: Int) {
            self.name = name
            self.byteCount = byteCount
        }
    }

    /// Each session as a file in a directory the app owns, appended to in place.
    struct _ConsoleSessionStorage: ConsoleSessionStorage {
        /// Application Support's folder named after the app, then `DebugDrawer/ConsoleSessions`,
        /// beside the Network plugin's sessions. Reset App State keeps it unless DebugDrawer's own
        /// files are included.
        static var defaultDirectory: URL {
            URL.applicationSupportDirectory
                .appending(path: Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName, directoryHint: .isDirectory)
                .appending(path: "DebugDrawer/ConsoleSessions", directoryHint: .isDirectory)
        }

        let directory: URL

        func sessionFiles() throws -> [ConsoleSessionFile] {
            guard FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) else { return [] }
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey])
            return files.compactMap { file in
                let values = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                guard values?.isRegularFile == true, file.pathExtension == "jsonl" else { return nil }
                return ConsoleSessionFile(name: file.lastPathComponent, byteCount: values?.fileSize ?? 0)
            }
        }

        func append(_ data: Data, toSessionNamed name: String) throws {
            let file = directory.appending(path: name, directoryHint: .notDirectory)
            // Created on each append that finds it gone, so a session deleted while the app runs
            // (Reset App State, say) starts again rather than failing every write after.
            if !FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                guard FileManager.default.createFile(atPath: file.path(percentEncoded: false), contents: nil) else {
                    throw CocoaError(.fileWriteUnknown)
                }
            }
            // Written straight to the file, not through a buffer of the process's own, so what
            // was appended survives the app crashing; nothing is synced to the disk, as only the
            // system going down would lose it.
            let handle = try FileHandle(forWritingTo: file)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        }

        func contents(ofSessionNamed name: String) throws -> Data {
            try Data(contentsOf: directory.appending(path: name, directoryHint: .notDirectory))
        }

        func deleteSession(named name: String) throws {
            do {
                try FileManager.default.removeItem(at: directory.appending(path: name, directoryHint: .notDirectory))
            } catch let error as CocoaError where error.code == .fileNoSuchFile {
                return
            }
        }
    }
#endif
