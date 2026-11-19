#if DEBUG
    import Combine
    import Foundation
    import os

    /// Where the browser is and what it shows, with the totals of the folders it has counted, and
    /// the changes it makes: imports, renames and deletes, none of them in the bundle.
    ///
    /// Main-actor isolated, like the drawer that shows it; the file system work runs off it.
    /// The view loads each place from `.task(id: request)`, so moving on cancels the reads and the
    /// counting for the place it left.
    @MainActor
    final class FileBrowserModel: ObservableObject {
        /// A place to load; a new one each time a place is shown, so showing the same place again
        /// reads it again.
        struct LoadRequest: Hashable, Sendable {
            let place: FileBrowserPlace
            let generation: Int
        }

        @Published private(set) var screen: FileBrowserScreen
        @Published private(set) var request = LoadRequest(place: .roots, generation: 0)
        /// The total size of each folder counted, by its path.
        @Published private(set) var folderSizes: [String: Int64] = [:]
        /// Why the last import, rename or delete failed, until another place is shown.
        @Published private(set) var failure: FileBrowserFailure?

        let roots: FileRoots
        private static let logger = Logger(subsystem: "DebugDrawerFileBrowserPlugin", category: "FileBrowserModel")
        private let fileSystem: any FileSystem
        /// The drawers the plugin is installed in; the last to remove it drops what was read.
        private var installations: Set<ObjectIdentifier> = []

        /// A browser of `roots`, read from and changed through `fileSystem`.
        init(roots: FileRoots, fileSystem: any FileSystem = LocalFileSystem()) {
            self.roots = roots
            self.fileSystem = fileSystem
            screen = .roots(roots, isEmpty: false)
        }

        /// Counts `drawer` as one the plugin is installed in.
        func install(in drawer: ObjectIdentifier) {
            installations.insert(drawer)
        }

        /// Uncounts `drawer`; once no drawer holds the plugin, goes back to the list of roots,
        /// dropping the listing, preview and folder totals read, and any failure. A read still
        /// running is for a place no longer shown, so it changes nothing.
        func uninstall(from drawer: ObjectIdentifier) {
            guard installations.remove(drawer) != nil, installations.isEmpty else { return }
            folderSizes = [:]
            show(.roots)
        }

        /// Shows `place`, loading until `load(_:)` reads it.
        func show(_ place: FileBrowserPlace) {
            failure = nil
            request = LoadRequest(place: place, generation: request.generation + 1)
            screen = switch place {
            case .roots: .roots(roots, isEmpty: false)
            case let .directory(root, url): .directory(DirectoryListing(root: root, url: url, contents: .loading))
            case let .file(root, item): .file(FileDetailState(root: root, item: item, preview: .loading))
            }
        }

        /// Shows the place one step up.
        func back() {
            show(request.place.parent)
        }

        /// Reads the place shown again, and counts its folders again.
        func refresh() {
            folderSizes = [:]
            show(request.place)
        }

        /// Reads what `request` shows, then counts the totals of the folders it lists, unless
        /// another place was shown first or the task is cancelled.
        func load(_ request: LoadRequest) async {
            guard request == self.request else { return }
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

        /// Copies the file at `source`, as the file importer picked it, into the folder shown,
        /// under a name of its own: "photo 2.png" beside a "photo.png". Never into the bundle.
        func importFile(from source: URL) async {
            guard case let .directory(root, directory) = request.place, !root.isReadOnly else { return }
            let destination = directory.appending(path: Self.uniqueName(for: source.lastPathComponent, besides: shownNames))
            let isScoped = source.startAccessingSecurityScopedResource()
            defer {
                if isScoped { source.stopAccessingSecurityScopedResource() }
            }
            do {
                try await fileSystem.copy(source, to: destination)
            } catch {
                fail("Couldn't import \(source.lastPathComponent)", error)
                return
            }
            refresh()
        }

        /// Renames `item` to `name`, then shows it under its new name if it was shown. Nothing in
        /// the bundle, and no root, is renamed.
        func rename(_ item: FileItem, to name: String) async {
            let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let root = request.place.root, canChange(item, in: root), name != item.name else { return }
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

        /// Deletes `item`, then shows its folder if it was shown. Nothing in the bundle, and no
        /// root, is deleted.
        func delete(_ item: FileItem) async {
            guard let root = request.place.root, canChange(item, in: root) else { return }
            do {
                try await fileSystem.remove(item.url)
            } catch {
                fail("Couldn't delete \(item.name)", error)
                return
            }
            folderSizes = [:]
            show(isShowing(item) ? request.place.parent : request.place)
        }

        /// The names in the folder shown.
        private var shownNames: Set<String> {
            guard case let .directory(listing) = screen, case let .loaded(contents) = listing.contents else { return [] }
            return Set(contents.items.map(\.name))
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
                return .loaded(DirectoryContents(directory: try await fileSystem.item(at: url), items: try await fileSystem.contents(of: url)))
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
        static func isFileName(_ name: String) -> Bool {
            !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\0")
        }

        /// `name`, or with " 2", " 3"… before its extension, the first that isn't in `taken`.
        static func uniqueName(for name: String, besides taken: Set<String>) -> String {
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
#endif
