import Foundation

// The app-group store's files, which both its server and its transport read and write. Each file
// holds one `StoreDocument` as JSON, a message with its schema version and writer (no frame: the
// file is the frame), written atomically, so a
// reader in another process sees the old file or the new one, never part of one.
//
//     <directory>/snapshots/<plugin ID>.json   each plugin's newest snapshot, replaced as it changes
//     <directory>/commands/<sequence>.json     commands waiting for the app, performed in name
//                                              order and removed
//
// Snapshots stay when the app is suspended or quits, so a viewer started later reads the last
// state; commands wait for the app to come back. A plugin ID is percent-encoded into its file name.
//
// A document is written to `<name>.json.<UUID>.partial` beside its file, then renamed over it
// (`write(_:to:)`), so a process killed while writing leaves only that partial file, under a name
// that isn't a message file's: readers never read it, and the last complete document stands. The
// store writes its own rather than through `Data.write(to:options: .atomic)`, as Foundation picks
// where its temporary file goes (beside the file, or a temporary-items folder elsewhere when
// sandboxed), and a cut-off one there would be out of the store's reach. No fsync: a killed
// process's writes still reach the disk; only a power loss could lose one. Cut-off files and
// waiting commands are what could grow, so the store is bounded:
//
//     snapshots/   one file per plugin ID the app serves, each its model's snapshot, which the
//                  plugin bounds; the app's server, the only writer here, removes every other file
//                  as it starts
//     commands/    at most `maximumCommandFiles` files and `maximumCommandBytes` bytes, cut-off
//                  files included: a viewer removes the oldest past either after leaving a
//                  command, and leaves no command larger than the byte budget
//
// Names order the commands (a viewer names each by the wall clock), so the oldest removed are
// those the app would have performed first. Cut-off commands aren't removed as the app starts:
// several viewers write there and one may be mid-write, so the budget bounds them instead.
// Rejected: a ring file the app appends to (a viewer wants each plugin's newest state, which the
// plugin's snapshot already holds, bounded; appending would need offsets and compaction two
// processes agree on), and removing cut-off files by age (a clock rule where the name already
// says what a file is).

/// Where the app-group store keeps its files under a directory.
package struct AppGroupStoreLayout: Sendable {
    /// The most files `commands` holds once a viewer has left a command.
    package static let maximumCommandFiles = 256
    /// The most bytes `commands` holds once a viewer has left a command; a larger command
    /// isn't left.
    package static let maximumCommandBytes = 16 << 20

    package let snapshots: URL
    package let commands: URL

    package init(directory: URL) {
        snapshots = directory.appending(path: "snapshots", directoryHint: .isDirectory)
        commands = directory.appending(path: "commands", directoryHint: .isDirectory)
    }

    /// Makes both directories, as either side may start first, and checks this process may read,
    /// write and search each; `false` when it can't, so the caller fails closed. The drawer's
    /// servers and transports use their own `create(otherwise:)`, which says why.
    package func create() -> Bool {
        do {
            try FileManager.default.createDirectory(at: snapshots, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: commands, withIntermediateDirectories: true)
        } catch {
            return false
        }
        return [snapshots, commands].allSatisfy { faccessat(AT_FDCWD, $0.path, R_OK | W_OK | X_OK, AT_EACCESS) == 0 }
    }

    /// The file holding `pluginID`'s snapshot.
    package func snapshotFile(for pluginID: String) -> URL {
        let name = pluginID.addingPercentEncoding(withAllowedCharacters: Self.fileNameCharacters) ?? pluginID
        return snapshots.appending(path: "\(name).json", directoryHint: .notDirectory)
    }

    /// The message files in `directory`, sorted by name; the temporary files an atomic write
    /// makes, and anything else, are left out.
    package func messageFiles(in directory: URL) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names
            .filter(Self.isMessageFile)
            .sorted()
            .map { directory.appending(path: $0, directoryHint: .notDirectory) }
    }

    /// Writes `data` to `file` atomically: a reader sees the old file or the new one, and a
    /// process killed part-way leaves the old one and a partial file beside it.
    ///
    /// - Throws: The error writing or renaming gave; the partial file is removed then.
    package func write(_ data: Data, to file: URL) throws {
        let partial = file.deletingLastPathComponent()
            .appending(path: "\(file.lastPathComponent).\(UUID().uuidString).partial", directoryHint: .notDirectory)
        do {
            try data.write(to: partial, options: .withoutOverwriting)
            guard rename(partial.path, file.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        } catch {
            try? FileManager.default.removeItem(at: partial)
            throw error
        }
    }

    /// Removes every file in `snapshots` that isn't a message file: what a cut-off write left.
    /// Only the app's server writes there, so it calls this before it writes.
    package func removeCutOffSnapshots() {
        for file in Self.files(in: snapshots) where !Self.isMessageFile(file.url.lastPathComponent) {
            try? FileManager.default.removeItem(at: file.url)
        }
    }

    /// Removes the oldest files in `commands`, cut-off ones among them, until it holds at most
    /// ``maximumCommandFiles`` files and ``maximumCommandBytes`` bytes.
    ///
    /// - Returns: How many files were removed.
    @discardableResult
    package func trimCommands() -> Int {
        var waiting = Self.files(in: commands)[...]
        var bytes = waiting.reduce(0) { $0 + $1.size }
        var removed = 0
        while let oldest = waiting.first, waiting.count > Self.maximumCommandFiles || bytes > Self.maximumCommandBytes {
            waiting = waiting.dropFirst()
            bytes -= oldest.size
            // The app may have performed it, or another viewer removed it, since it was
            // listed: either way it no longer counts.
            try? FileManager.default.removeItem(at: oldest.url)
            removed += 1
        }
        return removed
    }

    /// The regular files in `directory`, sorted by name, with their sizes.
    private static func files(in directory: URL) -> [StoreFile] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys))) ?? []
        return urls
            .compactMap { url in
                guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true else { return nil }
                return StoreFile(url: url, size: values.fileSize ?? 0)
            }
            .sorted { $0.url.lastPathComponent < $1.url.lastPathComponent }
    }

    private static func isMessageFile(_ name: String) -> Bool {
        name.hasSuffix(".json") && !name.hasPrefix(".")
    }

    private static let fileNameCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
}

/// A file in the store and its size in bytes.
private struct StoreFile {
    let url: URL
    let size: Int
}
