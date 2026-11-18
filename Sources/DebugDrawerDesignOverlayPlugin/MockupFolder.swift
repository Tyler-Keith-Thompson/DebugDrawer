#if DEBUG
    import DebugDrawer
    import Foundation

    /// The mockup and its settings in a folder, `Caches/DebugDrawer/DesignOverlay` in production
    /// (`Caches/<bundle identifier>/DebugDrawer/DesignOverlay` in a Mac app outside the App
    /// Sandbox): the system may clear it when the device runs short of space, which suits a comp
    /// that can be picked again. Its file work is the drawer's own, which Disk I/O leaves out.
    struct MockupFolder: MockupStorage {
        /// The folder; created when the first mockup or settings are saved.
        let directory: URL

        /// The running app's folder: `Caches/DebugDrawer/DesignOverlay` in its container, or in a Mac
        /// app outside the App Sandbox `Caches/<bundle identifier>/DebugDrawer/DesignOverlay`.
        static let standard = MockupFolder(
            directory: directory(
                cachesDirectory: .cachesDirectory,
                isSandboxed: isAppSandboxed,
                bundleIdentifier: Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName
            )
        )

        /// Where an app keeps its mockup and settings.
        ///
        /// A sandboxed app's Caches is its own, so the folder is `DebugDrawer/DesignOverlay` in it. A Mac
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
            return caches.appending(path: "DebugDrawer/DesignOverlay", directoryHint: .isDirectory)
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

        // The data as it was picked, in whatever format, under one name: Image I/O reads the format
        // from the bytes, so the extension would say nothing it needs.
        private var mockupURL: URL {
            directory.appending(path: "Mockup")
        }

        private var settingsURL: URL {
            directory.appending(path: "Settings.json")
        }

        func loadMockup() -> Data? {
            DebugDrawerActivity.$isDrawerWork.withValue(true) { try? Data(contentsOf: mockupURL) }
        }

        func saveMockup(_ data: Data) throws(MockupFailure) {
            let saved = DebugDrawerActivity.$isDrawerWork.withValue(true) {
                (try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)) != nil
                    && (try? data.write(to: mockupURL, options: .atomic)) != nil
            }
            guard saved else { throw .notSaved }
        }

        func removeMockup() {
            DebugDrawerActivity.$isDrawerWork.withValue(true) { try? FileManager.default.removeItem(at: mockupURL) }
        }

        func loadSettings() -> DesignOverlaySettings? {
            let data = DebugDrawerActivity.$isDrawerWork.withValue(true) { try? Data(contentsOf: settingsURL) }
            guard let data else { return nil }
            return try? JSONDecoder().decode(DesignOverlaySettings.self, from: data)
        }

        func saveSettings(_ settings: DesignOverlaySettings) {
            guard let data = try? JSONEncoder().encode(settings) else { return }
            DebugDrawerActivity.$isDrawerWork.withValue(true) {
                try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try? data.write(to: settingsURL, options: .atomic)
            }
        }
    }
#endif
