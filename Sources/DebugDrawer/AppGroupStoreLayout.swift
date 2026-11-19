import Foundation

// The app-group store's files, which both its server and its transport read and write. Each file
// holds one `TransportMessage` as JSON (no frame: the file is the frame), written atomically, so a
// reader in another process sees the old file or the new one, never part of one.
//
//     <directory>/snapshots/<plugin ID>.json   each plugin's newest snapshot, replaced as it changes
//     <directory>/commands/<sequence>.json     commands waiting for the app, performed in name
//                                              order and removed
//
// Snapshots stay when the app is suspended or quits, so a viewer started later reads the last
// state; commands wait for the app to come back. A plugin ID is percent-encoded into its file name.

#if DEBUG
    /// Where the app-group store keeps its files under a directory.
    struct AppGroupStoreLayout: Sendable {
        let snapshots: URL
        let commands: URL

        init(directory: URL) {
            snapshots = directory.appending(path: "snapshots", directoryHint: .isDirectory)
            commands = directory.appending(path: "commands", directoryHint: .isDirectory)
        }

        /// Makes both directories, as either side may start first; `false` when it can't.
        func create() -> Bool {
            do {
                try FileManager.default.createDirectory(at: snapshots, withIntermediateDirectories: true)
                try FileManager.default.createDirectory(at: commands, withIntermediateDirectories: true)
                return true
            } catch {
                return false
            }
        }

        /// The file holding `pluginID`'s snapshot.
        func snapshotFile(for pluginID: String) -> URL {
            let name = pluginID.addingPercentEncoding(withAllowedCharacters: Self.fileNameCharacters) ?? pluginID
            return snapshots.appending(path: "\(name).json", directoryHint: .notDirectory)
        }

        /// The message files in `directory`, sorted by name; the temporary files an atomic write
        /// makes, and anything else, are left out.
        func messageFiles(in directory: URL) -> [URL] {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
            return names
                .filter { $0.hasSuffix(".json") && !$0.hasPrefix(".") }
                .sorted()
                .map { directory.appending(path: $0, directoryHint: .notDirectory) }
        }

        private static let fileNameCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
    }
#endif
