#if DEBUG
    import DebugDrawer
    import Foundation

    /// The directories whose contents the Files and Caches categories delete, and what inside
    /// them is left to other categories.
    ///
    /// Only an area's contents are deleted, never the area itself, and links are deleted as
    /// links: nothing is followed out of an area, neither to list it nor to delete it.
    struct AppContainer: Sendable {
        /// The areas the Files category clears.
        let files: [FileArea]
        /// The areas the Caches category clears.
        let caches: [FileArea]
        /// Directories inside those areas that belong to another category, and are kept by this
        /// one: an app group's Library/Preferences (its UserDefaults suite) and Library/Caches.
        let kept: [URL]
        /// The folder named after the app inside an area, where DebugDrawer's plugins keep their
        /// files on a Mac, whose Application Support is shared by every app that isn't sandboxed.
        let appFolderName: String

        /// The prefix of what DebugDrawer keeps in an area or its app folder: `Caches/DebugDrawer`
        /// (recordings and mockups; in the app's folder outside the sandbox), `DebugDrawer Crash Reports` and `DebugDrawer MetricKit Payloads`.
        static let debugDrawerPrefix = "DebugDrawer"

        // Off the caller's actor, as is `delete`: a container's walk can take a while. Both are
        // the drawer's own work, which Disk I/O leaves out.

        /// What a category would delete from `areas`: each area's entries, by name, descending
        /// only into folders that hold something kept, so the rest of such a folder is listed and
        /// the kept item isn't.
        ///
        /// - Parameter includingDebugDrawer: Whether DebugDrawer's own files go too.
        @concurrent
        func entries(in areas: [FileArea], includingDebugDrawer: Bool) async -> [FileEntry] {
            DebugDrawerActivity.$isDrawerWork.withValue(true) {
                areas.flatMap { area -> [FileEntry] in
                    guard let root = Self.realDirectoryPath(area.directory) else { return [] }
                    var kept = Set(kept.map(Self.path))
                    if !includingDebugDrawer {
                        kept.formUnion(debugDrawerPaths(in: root))
                    }
                    return Self.entries(in: root, named: area.name, keeping: kept)
                }
            }
        }

        /// Deletes `entries`, links as links; one already gone is no failure.
        ///
        /// - Returns: The entries that couldn't be deleted, with why.
        @concurrent
        func delete(_ entries: [FileEntry]) async -> [ResetFailure] {
            DebugDrawerActivity.$isDrawerWork.withValue(true) {
                entries.compactMap { entry in
                    do {
                        try FileManager.default.removeItem(at: entry.url)
                        return nil
                    } catch let error as CocoaError where error.code == .fileNoSuchFile {
                        return nil
                    } catch {
                        return .file(entry.displayPath, reason: error.localizedDescription)
                    }
                }
            }
        }

        /// DebugDrawer's own items in the area at `root` and in its folder named after the app.
        private func debugDrawerPaths(in root: String) -> [String] {
            [root, root + "/" + appFolderName].flatMap { directory in
                let names = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
                return names.filter { $0.hasPrefix(Self.debugDrawerPrefix) }.map { directory + "/" + $0 }
            }
        }

        /// The entries in the directory at `path`, named from `displayPath`, leaving out `kept`
        /// and descending into a real directory that holds a kept item.
        private static func entries(in path: String, named displayPath: String, keeping kept: Set<String>) -> [FileEntry] {
            let names = ((try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []).sorted()
            return names.flatMap { name -> [FileEntry] in
                let child = path + "/" + name
                let display = displayPath + "/" + name
                if kept.contains(child) { return [] }
                if kept.contains(where: { $0.hasPrefix(child + "/") }), isRealDirectory(child) {
                    return entries(in: child, named: display, keeping: kept)
                }
                return [FileEntry(url: URL(filePath: child), displayPath: display, byteCount: byteCount(at: child))]
            }
        }

        /// The bytes of the regular files at `path`: the file's own, or those under a directory,
        /// whose links aren't followed.
        private static func byteCount(at path: String) -> Int64 {
            let attributes = try? FileManager.default.attributesOfItem(atPath: path)
            switch attributes?[.type] as? FileAttributeType {
            case .typeRegular?:
                return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
            case .typeDirectory?:
                let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
                let enumerator = FileManager.default.enumerator(at: URL(filePath: path), includingPropertiesForKeys: keys)
                var total: Int64 = 0
                while let url = enumerator?.nextObject() as? URL {
                    let values = try? url.resourceValues(forKeys: Set(keys))
                    if values?.isRegularFile == true { total += Int64(values?.fileSize ?? 0) }
                }
                return total
            default:
                return 0
            }
        }

        /// Whether `path` is a directory itself, not a link to one.
        private static func isRealDirectory(_ path: String) -> Bool {
            (try? FileManager.default.attributesOfItem(atPath: path))?[.type] as? FileAttributeType == .typeDirectory
        }

        /// `url`'s path with the links above it resolved, when it is a directory itself; `nil`
        /// when it is missing or a link, which would lead out of the container.
        private static func realDirectoryPath(_ url: URL) -> String? {
            let path = Self.path(url)
            return isRealDirectory(path) ? path : nil
        }

        /// `url`'s path with links resolved in the directories above it, not in its last
        /// component, so a link is compared as itself.
        private static func path(_ url: URL) -> String {
            let standardized = url.standardizedFileURL
            let parent = standardized.deletingLastPathComponent().resolvingSymlinksInPath().path(percentEncoded: false)
            let name = standardized.lastPathComponent
            return (parent.hasSuffix("/") ? parent : parent + "/") + name
        }
    }

    extension AppContainer {
        /// The running app's areas.
        ///
        /// On iOS, tvOS and visionOS, and in a sandboxed Mac app, the app's container is its own:
        /// Files clears Documents, Application Support and tmp, and Caches clears Library/Caches.
        /// A Mac app that isn't sandboxed shares those with every other app, so Files clears only
        /// Application Support's folder named after the app, Caches only Caches' one (where
        /// URLCache keeps its store), and neither touches Documents or the temporary directory.
        ///
        /// - Parameters:
        ///   - appGroups: The app groups whose containers are cleared too: each container's files,
        ///     less its Library/Preferences and Library/Caches, and its Library/Caches.
        ///   - directories: More directories whose contents count as the app's files.
        ///   - appFolderName: The app's bundle identifier.
        static func current(appGroups: [String], directories: [URL], appFolderName: String) -> AppContainer {
            var files = isSandboxed
                ? [
                    FileArea(name: "Documents", directory: .documentsDirectory),
                    FileArea(name: "Application Support", directory: .applicationSupportDirectory),
                    FileArea(name: "tmp", directory: .temporaryDirectory)
                ]
                : [FileArea(name: "Application Support/\(appFolderName)", directory: .applicationSupportDirectory.appending(path: appFolderName))]
            var caches = isSandboxed
                ? [FileArea(name: "Caches", directory: .cachesDirectory)]
                : [FileArea(name: "Caches/\(appFolderName)", directory: .cachesDirectory.appending(path: appFolderName))]
            var kept: [URL] = []
            for group in appGroups {
                guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else { continue }
                let library = container.appending(path: "Library", directoryHint: .isDirectory)
                files.append(FileArea(name: group, directory: container))
                caches.append(FileArea(name: "\(group)/Library/Caches", directory: library.appending(path: "Caches")))
                kept += [library.appending(path: "Preferences"), library.appending(path: "Caches")]
            }
            files += directories.map { FileArea(name: $0.lastPathComponent, directory: $0) }
            return AppContainer(files: files, caches: caches, kept: kept, appFolderName: appFolderName)
        }

        /// Whether the app's directories are its own: always on iOS, tvOS and visionOS; on the Mac
        /// and in Mac Catalyst only in the App Sandbox, which names the container in the
        /// environment.
        static var isSandboxed: Bool {
            #if os(macOS) || targetEnvironment(macCatalyst)
                ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
            #else
                true
            #endif
        }
    }
#endif
