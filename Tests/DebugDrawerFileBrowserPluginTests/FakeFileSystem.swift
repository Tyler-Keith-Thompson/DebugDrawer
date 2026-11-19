#if DEBUG
    @testable import DebugDrawerFileBrowserPlugin
    import Foundation
    import os

    /// A file system in memory that behaves as the real one does for the calls the browser makes:
    /// a folder lists what is directly in it, in no particular order (here, reverse path order, so
    /// a test sees the model sort); a total counts every file below a folder; a read stops at its
    /// limit; a move or copy refuses a destination that exists. A path can be made unreadable, and
    /// every change refused, as a locked volume does. It records each call, in order.
    final class FakeFileSystem: FileSystem {
        /// A call the browser made, by path.
        enum Call: Equatable, Sendable {
            case item(String)
            case contents(String)
            case totalSize(String)
            case read(String, upTo: Int)
            case remove(String)
            case move(String, to: String)
            case copy(String, to: String)
        }

        private struct Entry: Sendable {
            /// The file's bytes, or `nil` for a folder.
            var data: Data?
        }

        private struct State: Sendable {
            var entries: [String: Entry] = [:]
            var calls: [Call] = []
            var unreadable: Set<String> = []
            var refusesChanges = false
        }

        /// When every file and folder was modified.
        static let modified = Date(timeIntervalSinceReferenceDate: 800_000_000)
        /// When every file and folder was created.
        static let created = Date(timeIntervalSinceReferenceDate: 790_000_000)
        /// What a change throws once changes are refused.
        static let refusal = CocoaError(.fileWriteNoPermission)
        /// What reading an unreadable path throws.
        static let unreadable = CocoaError(.fileReadNoPermission)
        /// What reading a path that doesn't exist throws.
        static let missing = CocoaError(.fileReadNoSuchFile)

        private let state = OSAllocatedUnfairLock(initialState: State())

        /// A file system holding `files`, by path, and the folders `directories`, with every
        /// folder above them.
        init(files: [String: Data] = [:], directories: [String] = []) {
            for directory in directories {
                makeDirectory(directory)
            }
            for (path, data) in files {
                write(data, to: path)
            }
        }

        /// The calls made, in order.
        var calls: [Call] {
            state.withLock { $0.calls }
        }

        /// Writes `data` to the file at `path`, making the folders above it.
        func write(_ data: Data, to path: String) {
            state.withLock { state in
                Self.makeParents(of: path, in: &state)
                state.entries[path] = Entry(data: data)
            }
        }

        /// Makes the folder at `path` and every folder above it.
        func makeDirectory(_ path: String) {
            state.withLock { state in
                Self.makeParents(of: path, in: &state)
                state.entries[path] = Entry(data: nil)
            }
        }

        /// Makes reading the file or folder at `path` throw ``unreadable``.
        func makeUnreadable(_ path: String) {
            state.withLock { _ = $0.unreadable.insert(path) }
        }

        /// Makes every remove, move and copy from now on throw ``refusal``.
        func refuseChanges() {
            state.withLock { $0.refusesChanges = true }
        }

        /// Whether a file or folder is at `path`.
        func exists(_ path: String) -> Bool {
            state.withLock { $0.entries[path] != nil }
        }

        /// The bytes of the file at `path`.
        func data(at path: String) -> Data? {
            state.withLock { $0.entries[path]?.data }
        }

        func item(at url: URL) async throws -> FileItem {
            let path = url.filePath
            let entry = try state.withLock { state in
                state.calls.append(.item(path))
                return try Self.readable(path, in: state)
            }
            return FileItem(
                url: url, isDirectory: entry.data == nil, size: Int64(entry.data?.count ?? 0), modified: Self.modified, created: Self.created
            )
        }

        func contents(of url: URL) async throws -> [FileItem] {
            let path = url.filePath
            return try state.withLock { state in
                state.calls.append(.contents(path))
                guard try Self.readable(path, in: state).data == nil else { throw Self.missing }
                return state.entries
                    .filter { Self.parent(of: $0.key) == path }
                    .sorted { $0.key > $1.key }
                    .map { child, entry in
                        FileItem(
                            url: URL(filePath: child, directoryHint: entry.data == nil ? .isDirectory : .notDirectory),
                            isDirectory: entry.data == nil,
                            size: Int64(entry.data?.count ?? 0),
                            modified: Self.modified,
                            created: Self.created
                        )
                    }
            }
        }

        func totalSize(of url: URL) async throws(CancellationError) -> Int64 {
            let path = url.filePath
            if Task.isCancelled { throw CancellationError() }
            return state.withLock { state in
                state.calls.append(.totalSize(path))
                return state.entries
                    .filter { $0.key.hasPrefix(path + "/") && !state.unreadable.contains($0.key) }
                    .compactMap { $0.value.data?.count }
                    .reduce(0) { $0 + Int64($1) }
            }
        }

        func read(_ url: URL, upTo limit: Int) async throws -> Data {
            let path = url.filePath
            return try state.withLock { state in
                state.calls.append(.read(path, upTo: limit))
                guard let data = try Self.readable(path, in: state).data else { throw CocoaError(.fileReadUnknown) }
                return data.prefix(limit)
            }
        }

        func remove(_ url: URL) async throws {
            let path = url.filePath
            try state.withLock { state in
                state.calls.append(.remove(path))
                guard !state.refusesChanges else { throw Self.refusal }
                guard state.entries[path] != nil else { throw CocoaError(.fileNoSuchFile) }
                state.entries = state.entries.filter { $0.key != path && !$0.key.hasPrefix(path + "/") }
            }
        }

        func move(_ url: URL, to destination: URL) async throws {
            let (path, target) = (url.filePath, destination.filePath)
            try state.withLock { state in
                state.calls.append(.move(path, to: target))
                let moved = try Self.subtree(at: path, to: target, in: state)
                state.entries = state.entries.filter { $0.key != path && !$0.key.hasPrefix(path + "/") }
                state.entries.merge(moved) { _, new in new }
            }
        }

        func copy(_ url: URL, to destination: URL) async throws {
            let (path, target) = (url.filePath, destination.filePath)
            try state.withLock { state in
                state.calls.append(.copy(path, to: target))
                let copied = try Self.subtree(at: path, to: target, in: state)
                state.entries.merge(copied) { _, new in new }
            }
        }

        /// The entry at `path`, unless it is unreadable or missing.
        private static func readable(_ path: String, in state: State) throws(CocoaError) -> Entry {
            guard !state.unreadable.contains(path) else { throw unreadable }
            guard let entry = state.entries[path] else { throw missing }
            return entry
        }

        /// The entries at and under `path`, at `target` instead, when a change may make them.
        private static func subtree(at path: String, to target: String, in state: State) throws(CocoaError) -> [String: Entry] {
            guard !state.refusesChanges else { throw refusal }
            guard state.entries[path] != nil else { throw CocoaError(.fileNoSuchFile) }
            guard state.entries[target] == nil else { throw CocoaError(.fileWriteFileExists) }
            var moved: [String: Entry] = [:]
            for (key, entry) in state.entries where key == path || key.hasPrefix(path + "/") {
                moved[target + key.dropFirst(path.count)] = entry
            }
            return moved
        }

        private static func makeParents(of path: String, in state: inout State) {
            var parent = parent(of: path)
            while parent != "/", state.entries[parent] == nil {
                state.entries[parent] = Entry(data: nil)
                parent = Self.parent(of: parent)
            }
        }

        private static func parent(of path: String) -> String {
            URL(filePath: path).deletingLastPathComponent().filePath
        }
    }
#endif
