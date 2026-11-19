import Combine
import DebugDrawer
import Foundation
import os

#if DEBUG
    // The file system is read and changed through `FileSystem`, and the app's folders and app
    // group containers come from `FileLocations`; the model holds values only. Going to a place
    // lands at once, so the view shows it loading on the next frame, and the read starts as a task
    // of its own, cancelled by the next place shown or once no view reads. Imports, renames and
    // deletes run as model tasks, each after the one sent before it, and a read waits for those
    // sent before it, so a listing never shows a file a delete sent first has removed.

    /// The File Browser plugin's state and behavior, without its views: where the browser is,
    /// what it shows there, the folder totals counted so far and why the last change failed, read
    /// as a ``FileBrowserSnapshot`` and changed with a ``FileBrowserCommand``.
    ///
    /// The plugin's view reaches it through a `DebugDrawerPluginTransport`:
    ///
    /// ```swift
    /// let transport = DebugDrawerPluginTransport.direct(to: FileBrowserModel.shared)
    /// ```
    ///
    /// `FileBrowser.install(appGroups:)` sets the app groups whose containers it lists. Nothing is
    /// read until a view of it appears. Release builds get a stand-in whose snapshot holds nothing
    /// and which ignores every command.
    @MainActor
    public final class FileBrowserModel: DebugDrawerPluginModel {
        /// A place to read, numbered each time a place is shown, so a read for one shown before
        /// lands nowhere, and showing the same place again reads it again.
        private struct LoadRequest: Equatable {
            let place: FileBrowserPlace
            let generation: Int
        }

        /// The model over the app's own folders, its bundle and the containers of the app groups
        /// `FileBrowser.install(appGroups:)` names, which the plugin shows.
        public static let shared = FileBrowserModel()

        @Published private var screen: FileBrowserScreen
        /// The total size of each folder counted, by its path.
        @Published private var folderSizes: [String: Int64] = [:]
        @Published private var failure: FileBrowserFailure?

        /// The folders the browser starts from.
        private(set) var roots: FileRoots
        private let locations: any FileLocations
        private let fileSystem: any FileSystem
        private static let logger = Logger(subsystem: "DebugDrawerFileBrowserPlugin", category: "FileBrowserModel")
        /// The drawers the plugin is installed in; the last to remove it drops what was read.
        private var installations: Set<ObjectIdentifier> = []
        /// The views reading: each `startReading` not yet stopped.
        private var readers = 0
        private var request = LoadRequest(place: .roots, generation: 0)
        /// The read of the place shown and the count of its folders.
        private var loading: Task<Void, Never>?
        /// The last import, rename or delete started, which the next, and every read, waits for.
        private var work: Task<Void, Never>?

        /// A browser of the app's folders in `locations` and the containers of `appGroups`.
        ///
        /// - Parameters:
        ///   - locations: Where the app's folders, bundle and app group containers are.
        ///   - appGroups: The app groups whose containers to list.
        ///   - fileSystem: The file system to read and change.
        init(locations: any FileLocations = _FileLocations(), appGroups: [String] = [], fileSystem: any FileSystem = _FileSystem()) {
            self.locations = locations
            self.fileSystem = fileSystem
            roots = FileRoots(locations: locations, appGroups: appGroups)
            screen = .roots(roots, isEmpty: false)
        }

        public var snapshot: FileBrowserSnapshot {
            FileBrowserSnapshot(screen: screen, folderSizes: folderSizes, failure: failure)
        }

        public func perform(_ command: FileBrowserCommand) {
            switch command.action {
            case let .open(place):
                show(place)
            case .back:
                show(request.place.parent)
            case .refresh:
                refresh()
            case .startReading:
                readers += 1
                read()
            case .stopReading:
                stopReading()
            case let .importFile(source):
                enqueueImport(from: source)
            case let .rename(item, name):
                enqueueRename(of: item, to: name)
            case let .delete(item):
                enqueueDelete(of: item)
            }
        }

        /// Lists the containers of `appGroups` in place of those listed before, and goes back to
        /// the list of roots.
        func setAppGroups(_ appGroups: [String]) {
            roots = FileRoots(locations: locations, appGroups: appGroups)
            folderSizes = [:]
            show(.roots)
        }

        /// Counts `drawer` as one the plugin is installed in; nothing is read until it is shown.
        func install(in drawer: ObjectIdentifier) {
            installations.insert(drawer)
        }

        /// Uncounts `drawer`; once no drawer holds the plugin, goes back to the list of roots,
        /// dropping the listing, preview and folder totals read, and any failure, without reading
        /// them again. A read still running is for a place no longer shown, so it changes nothing.
        func uninstall(from drawer: ObjectIdentifier) {
            guard installations.remove(drawer) != nil, installations.isEmpty else { return }
            loading?.cancel()
            folderSizes = [:]
            failure = nil
            request = LoadRequest(place: .roots, generation: request.generation + 1)
            screen = .roots(roots, isEmpty: false)
        }

        /// Shows `place`, loading, and reads it while a view reads.
        private func show(_ place: FileBrowserPlace) {
            failure = nil
            request = LoadRequest(place: place, generation: request.generation + 1)
            screen = switch place {
            case .roots: .roots(roots, isEmpty: false)
            case let .directory(root, url): .directory(DirectoryListing(root: root, url: url, contents: .loading))
            case let .file(root, item): .file(FileDetailState(root: root, item: item, preview: .loading))
            }
            read()
        }

        /// Shows the place shown again, and counts its folders again.
        private func refresh() {
            folderSizes = [:]
            show(request.place)
        }

        /// Reads the place shown, once the changes sent before are done, in place of a read under
        /// way; while no view reads, reads nothing.
        private func read() {
            loading?.cancel()
            guard readers > 0 else { return }
            let request = request
            loading = Task { [work] in
                await work?.value
                await self.load(request)
            }
        }

        /// Ends one view's reading; once none reads, stops the read under way.
        private func stopReading() {
            readers = max(readers - 1, 0)
            if readers == 0 {
                loading?.cancel()
            }
        }

        /// Queues an import into the folder shown now, unless it is in the bundle.
        private func enqueueImport(from source: URL) {
            guard case let .directory(root, directory) = request.place, !root.isReadOnly else { return }
            enqueue { model in await model.importFile(from: source, into: directory) }
        }

        /// Queues renaming `item`, under the root shown now, unless it is the root or in the bundle.
        private func enqueueRename(of item: FileItem, to name: String) {
            guard let root = request.place.root, canChange(item, in: root) else { return }
            enqueue { model in await model.rename(item, to: name, in: root) }
        }

        /// Queues deleting `item`, under the root shown now, unless it is the root or in the bundle.
        private func enqueueDelete(of item: FileItem) {
            guard let root = request.place.root, canChange(item, in: root) else { return }
            enqueue { model in await model.delete(item) }
        }

        /// Starts `body` once the change started before it is done.
        private func enqueue(_ body: @escaping @MainActor (FileBrowserModel) async -> Void) {
            work = Task { [previous = work] in
                await previous?.value
                await body(self)
            }
        }

        /// Reads what `request` shows, then counts the totals of the folders it lists, unless
        /// another place was shown first or the task is cancelled.
        private func load(_ request: LoadRequest) async {
            guard request == self.request, !Task.isCancelled else { return }
            switch request.place {
            case .roots:
                let isEmpty = await rootsAreEmpty()
                guard request == self.request, !Task.isCancelled else { return }
                screen = .roots(roots, isEmpty: isEmpty)
                await count(roots.available.map(\.url))
            case let .directory(root, url):
                let contents = await contents(of: url)
                guard request == self.request, !Task.isCancelled else { return }
                screen = .directory(DirectoryListing(root: root, url: url, contents: contents))
                if case let .loaded(contents) = contents {
                    await count(contents)
                }
            case let .file(root, item):
                let fileSystem = fileSystem
                let current = (try? await fileSystem.item(at: item.url)) ?? item
                let preview: Loadable<FilePreview>
                do {
                    preview = .loaded(try await FilePreview.reading(current, from: fileSystem))
                } catch {
                    preview = .failed(error.localizedDescription)
                }
                guard request == self.request, !Task.isCancelled else { return }
                screen = .file(FileDetailState(root: root, item: current, preview: preview))
            }
        }

        /// Copies the file at `source` into `directory`, under a name nothing there has yet:
        /// "photo 2.png" beside a "photo.png".
        private func importFile(from source: URL, into directory: URL) async {
            // The names in the folder now, not as last listed: an import sent just before may
            // have added one the listing doesn't show yet.
            let taken = Set(((try? await fileSystem.contents(of: directory)) ?? []).map(\.name))
            let destination = directory.appending(path: Self.uniqueName(for: source.lastPathComponent, besides: taken))
            do {
                try await fileSystem.copy(source, to: destination)
            } catch {
                fail("Couldn't import \(source.lastPathComponent)", error)
                return
            }
            refresh()
        }

        /// Renames `item`, under `root`, to `name`, then shows it under its new name if it was
        /// shown.
        private func rename(_ item: FileItem, to name: String, in root: FileRoot) async {
            let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard name != item.name else { return }
            guard Self.isFileName(name) else {
                failure = FileBrowserFailure(title: "Couldn't rename \(item.name)", reason: "“\(name)” can't be a file name.")
                return
            }
            let destination = item.url.deletingLastPathComponent()
                .appending(path: name, directoryHint: item.isDirectory ? .isDirectory : .notDirectory)
            do {
                try await fileSystem.move(item.url, to: destination)
            } catch {
                fail("Couldn't rename \(item.name)", error)
                return
            }
            folderSizes = [:]
            guard isShowing(item) else {
                show(request.place)
                return
            }
            if item.isDirectory {
                show(.directory(root, destination))
            } else {
                show(.file(root, (try? await fileSystem.item(at: destination)) ?? item.renamed(to: destination)))
            }
        }

        /// Deletes `item`, then shows its folder if it was shown.
        private func delete(_ item: FileItem) async {
            do {
                try await fileSystem.remove(item.url)
            } catch {
                fail("Couldn't delete \(item.name)", error)
                return
            }
            folderSizes = [:]
            show(isShowing(item) ? request.place.parent : request.place)
        }

        /// Whether no root the app can change holds anything: the bundle never counts, and a
        /// folder that doesn't exist yet or can't be read counts as empty.
        private func rootsAreEmpty() async -> Bool {
            for root in roots.available where !root.isReadOnly {
                if let items = try? await fileSystem.contents(of: root.url), !items.isEmpty {
                    return false
                }
            }
            return true
        }

        private func contents(of url: URL) async -> Loadable<DirectoryContents> {
            do {
                let directory = try await fileSystem.item(at: url)
                let items = try await fileSystem.contents(of: url).sortedForDisplay()
                return .loaded(DirectoryContents(directory: directory, items: items))
            } catch {
                return .failed(error.localizedDescription)
            }
        }

        /// Counts each folder's total, one after another, until the task is cancelled.
        private func count(_ folders: [URL]) async {
            for folder in folders {
                guard let size = try? await fileSystem.totalSize(of: folder) else { return }
                folderSizes[folder.filePath] = size
            }
        }

        /// Counts the totals of the folders in `contents`, then the folder's own: its files' sizes
        /// and those totals, so its tree is walked once.
        private func count(_ contents: DirectoryContents) async {
            let folders = contents.items.filter(\.isDirectory).map(\.url)
            await count(folders)
            let counted = folders.compactMap { folderSizes[$0.filePath] }
            guard counted.count == folders.count else { return }
            folderSizes[contents.directory.path] = counted.reduce(0, +) + contents.items.map(\.size).reduce(0, +)
        }

        private func canChange(_ item: FileItem, in root: FileRoot) -> Bool {
            !root.isReadOnly && !item.url.isSameFile(as: root.url)
        }

        private func isShowing(_ item: FileItem) -> Bool {
            switch request.place {
            case .roots: false
            case let .directory(_, url): url.isSameFile(as: item.url)
            case let .file(_, shown): shown.url.isSameFile(as: item.url)
            }
        }

        private func fail(_ action: String, _ error: any Error) {
            Self.logger.error("\(action, privacy: .private): \(error.localizedDescription, privacy: .private)")
            failure = FileBrowserFailure(title: action, reason: error.localizedDescription)
        }

        /// Whether `name` names a file: not empty, ".", "..", and with no slash or NUL.
        nonisolated static func isFileName(_ name: String) -> Bool {
            !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\0")
        }

        /// `name`, or with " 2", " 3"… before its extension, the first that isn't in `taken`.
        nonisolated static func uniqueName(for name: String, besides taken: Set<String>) -> String {
            guard taken.contains(name) else { return name }
            let url = URL(filePath: name)
            let stem = url.deletingPathExtension().lastPathComponent
            let suffix = url.pathExtension.isEmpty ? "" : "." + url.pathExtension
            return (2...).lazy.map { "\(stem) \($0)\(suffix)" }.first { !taken.contains($0) } ?? name
        }
    }

    extension FileItem {
        /// The item at `url`, otherwise as it was.
        fileprivate func renamed(to url: URL) -> FileItem {
            FileItem(url: url, isDirectory: isDirectory, size: size, modified: modified, created: created)
        }
    }

    extension [FileItem] {
        /// Folders first, then by name as Finder sorts them: "file2" before "file10", ignoring case.
        fileprivate func sortedForDisplay() -> [FileItem] {
            sorted { lhs, rhs in
                lhs.isDirectory != rhs.isDirectory ? lhs.isDirectory : lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
        }
    }

    extension FilePreview {
        /// The preview of `item`, read from `fileSystem` off the caller's actor: its first
        /// ``readLimit`` bytes, or an image's first ``imageReadLimit``.
        @concurrent
        static func reading(_ item: FileItem, from fileSystem: any FileSystem) async throws -> FilePreview {
            let data = try await fileSystem.read(item.url, upTo: readLimit)
            guard data.count >= readLimit, isImage(data) else {
                return FilePreview(data: data, isTruncated: Int64(data.count) < item.size)
            }
            let image = try await fileSystem.read(item.url, upTo: imageReadLimit)
            return FilePreview(data: image, isTruncated: Int64(image.count) < item.size)
        }
    }
#else
    // The release stand-in: the same members, and nothing behind them.

    /// Release builds read no files: this stand-in's snapshot holds nothing, and it ignores every
    /// command.
    @MainActor
    public final class FileBrowserModel: DebugDrawerPluginModel {
        /// The stand-in model.
        public static let shared = FileBrowserModel()

        private init() {}

        /// Always empty.
        public var snapshot: FileBrowserSnapshot {
            FileBrowserSnapshot()
        }

        /// Does nothing.
        ///
        /// - Parameter command: Ignored.
        public func perform(_ command: FileBrowserCommand) {}
    }
#endif
