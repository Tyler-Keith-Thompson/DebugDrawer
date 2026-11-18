#if DEBUG
    import DebugDrawer
    import Foundation

    /// The mockup and its settings in a folder, `Caches/DebugDrawer/DesignOverlay` in production:
    /// the system may clear it when the device runs short of space, which suits a comp that can be
    /// picked again. Its file work is the drawer's own, which Disk I/O leaves out.
    struct MockupFolder: MockupStorage {
        /// The folder; created when the first mockup or settings are saved.
        let directory: URL

        /// `Caches/DebugDrawer/DesignOverlay` in the app's container.
        static let standard = MockupFolder(
            directory: URL.cachesDirectory.appending(path: "DebugDrawer/DesignOverlay", directoryHint: .isDirectory)
        )

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
