#if DEBUG
    import AVFoundation
    import DebugDrawer
    import Foundation

    /// The folder the recordings are saved in, `Caches/DebugDrawer/Recordings` in production
    /// (`Caches/<bundle identifier>/DebugDrawer/Recordings` in a Mac app outside the App Sandbox):
    /// the system may clear it when the device runs short of space, which suits movies made only
    /// to attach to a bug.
    ///
    /// Each movie is named for the moment it started (`Screen Recording 2026-11-16T10-46-40Z.mov`),
    /// which is where the list reads its start time from. Its file work is the drawer's own, which
    /// Disk I/O leaves out.
    struct RecordingFolder: Sendable {
        /// The folder; created when the first recording starts.
        let directory: URL

        /// The running app's folder: `Caches/DebugDrawer/Recordings` in its container, or in a Mac
        /// app outside the App Sandbox `Caches/<bundle identifier>/DebugDrawer/Recordings`.
        static let standard = RecordingFolder(
            directory: directory(
                cachesDirectory: .cachesDirectory,
                isSandboxed: isAppSandboxed,
                bundleIdentifier: Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName
            )
        )

        /// Where an app keeps its recordings.
        ///
        /// A sandboxed app's Caches is its own, so the folder is `DebugDrawer/Recordings` in it. A Mac
        /// app outside the sandbox shares Caches with every other such app, so the folder goes in
        /// the app's own `<bundle identifier>` folder there, which App State Reset clears and no
        /// other app reads.
        ///
        /// - Parameters:
        ///   - cachesDirectory: The app's Caches directory.
        ///   - isSandboxed: Whether that directory is the app's own.
        ///   - bundleIdentifier: The app's bundle identifier.
        /// - Returns: The folder.
        static func directory(cachesDirectory: URL, isSandboxed: Bool, bundleIdentifier: String) -> URL {
            let caches = isSandboxed ? cachesDirectory : cachesDirectory.appending(path: bundleIdentifier, directoryHint: .isDirectory)
            return caches.appending(path: "DebugDrawer/Recordings", directoryHint: .isDirectory)
        }

        // The same test as App State Reset's AppContainer.isSandboxed, duplicated on purpose:
        // plugins are vertical modules with no shared helper target, and the two must agree for
        // App State Reset to clear this folder.
        /// Whether the app's directories are its own: always on iOS, tvOS and visionOS; on the Mac
        /// and in Mac Catalyst only in the App Sandbox, which names the container in the
        /// environment.
        static var isAppSandboxed: Bool {
            #if os(macOS) || targetEnvironment(macCatalyst)
                ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
            #else
                true
            #endif
        }

        /// Where a recording started at `date` is written: named for the time, with ` 2`, ` 3` and
        /// so on added when one of that second is already there. Creates the folder.
        ///
        /// - Throws: `RecordingFailure.writeFailed` when the folder can't be created.
        func url(forRecordingStartedAt date: Date) throws(RecordingFailure) -> URL {
            let created = DebugDrawerActivity.$isDrawerWork.withValue(true) {
                (try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)) != nil
            }
            guard created else { throw .writeFailed }
            let base = "\(Self.namePrefix)\(Self.timestamp(of: date))"
            let candidates = [base] + (2 ... 100).map { "\(base) \($0)" }
            let free = candidates.lazy
                .map { directory.appending(path: "\($0).\(Self.fileExtension)") }
                .first { !FileManager.default.fileExists(atPath: $0.path) }
            // A hundred recordings in one second can't happen: each takes at least a display frame
            // and a write. Should it, the last name is reused and its movie replaced.
            return free ?? directory.appending(path: "\(candidates.last ?? base).\(Self.fileExtension)")
        }

        /// The saved recordings, newest first, each with its length read from the movie. Files that
        /// aren't recordings are left out.
        func recordings() async -> [Recording] {
            let keys: [URLResourceKey] = [.fileSizeKey, .creationDateKey]
            let urls = DebugDrawerActivity.$isDrawerWork.withValue(true) {
                (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)) ?? []
            }
            var recordings: [Recording] = []
            for url in urls where url.pathExtension == Self.fileExtension && url.lastPathComponent.hasPrefix(Self.namePrefix) {
                let values = try? url.resourceValues(forKeys: Set(keys))
                let started = Self.startDate(ofFileNamed: url.deletingPathExtension().lastPathComponent)
                    ?? values?.creationDate
                    ?? .distantPast
                let duration = try? await AVURLAsset(url: url).load(.duration)
                recordings.append(Recording(
                    url: url,
                    started: started,
                    duration: duration.flatMap { $0.isNumeric ? Duration.seconds($0.seconds) : nil },
                    byteCount: Int64(values?.fileSize ?? 0)
                ))
            }
            // Newest first; two of the same second by name, so " 2" lists above the first.
            return recordings.sorted {
                ($0.started, $0.url.lastPathComponent.count, $0.url.lastPathComponent)
                    > ($1.started, $1.url.lastPathComponent.count, $1.url.lastPathComponent)
            }
        }

        /// Deletes `url`; one already gone is no error.
        func delete(_ url: URL) {
            DebugDrawerActivity.$isDrawerWork.withValue(true) {
                try? FileManager.default.removeItem(at: url)
            }
        }

        /// Deletes the oldest of `recordings` (newest first) past the first `capacity`.
        ///
        /// - Returns: The ones kept.
        func prune(_ recordings: [Recording], keeping capacity: Int) -> [Recording] {
            for recording in recordings.dropFirst(capacity) {
                delete(recording.url)
            }
            return Array(recordings.prefix(capacity))
        }

        static let namePrefix = "Screen Recording "
        static let fileExtension = "mov"

        /// `date` in ISO 8601, in UTC, with `-` for `:`, which file systems may reserve.
        static func timestamp(of date: Date) -> String {
            ISO8601DateFormatter().string(from: date).replacingOccurrences(of: ":", with: "-")
        }

        /// The start time a recording's file name gives, or `nil` when it gives none.
        static func startDate(ofFileNamed name: String) -> Date? {
            guard name.hasPrefix(namePrefix) else { return nil }
            // "2026-11-16T10-46-40Z", then " 2" for a second recording of the same second.
            let stamp = name.dropFirst(namePrefix.count).prefix { $0 != " " }
            guard let time = stamp.split(separator: "T").last, stamp.split(separator: "T").count == 2 else { return nil }
            let date = stamp.split(separator: "T")[0]
            return ISO8601DateFormatter().date(from: "\(date)T\(time.replacingOccurrences(of: "-", with: ":"))")
        }
    }
#endif
