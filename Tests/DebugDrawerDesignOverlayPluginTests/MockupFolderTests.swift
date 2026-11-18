#if DEBUG
    import CoreGraphics
    @testable import DebugDrawerDesignOverlayPlugin
    import Foundation
    import Testing

    @Suite
    struct MockupFolderTests {
        @Test("Outside the App Sandbox the folder is Caches/<bundle identifier>/DebugDrawer/DesignOverlay")
        func unsandboxed() {
            let caches = URL(filePath: "/Users/someone/Library/Caches", directoryHint: .isDirectory)
            let expected = "/Users/someone/Library/Caches/com.example.shop/DebugDrawer/DesignOverlay"

            let actual = MockupFolder.directory(cachesDirectory: caches, isSandboxed: false, bundleIdentifier: "com.example.shop")

            #expect(actual.path == expected)
        }

        @Test("In a sandboxed app, as on iOS, the folder is Caches/DebugDrawer/DesignOverlay")
        func sandboxed() {
            let caches = URL(filePath: "/containers/shop/Library/Caches", directoryHint: .isDirectory)
            let expected = "/containers/shop/Library/Caches/DebugDrawer/DesignOverlay"

            let actual = MockupFolder.directory(cachesDirectory: caches, isSandboxed: true, bundleIdentifier: "com.example.shop")

            #expect(actual.path == expected)
        }

        @Test("The standard folder is in the app's own Caches folder on a Mac outside the sandbox, and in Caches/DebugDrawer on iOS")
        func standard() {
            #if os(macOS) || targetEnvironment(macCatalyst)
                // The test runner isn't sandboxed.
                let bundleIdentifier = Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName
                let expected = URL.cachesDirectory.appending(path: "\(bundleIdentifier)/DebugDrawer/DesignOverlay").standardizedFileURL.path
            #else
                let expected = URL.cachesDirectory.appending(path: "DebugDrawer/DesignOverlay").standardizedFileURL.path
            #endif

            let actual = MockupFolder.standard.directory.standardizedFileURL.path

            #expect(actual == expected)
        }

        @Test("A saved mockup reads back byte for byte, creating the folder, and a second replaces the first")
        func saveAndLoad() throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).appending(path: "DesignOverlay")
            defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
            let sut = MockupFolder(directory: directory)
            let first = MockupFixture.png(width: 10, height: 10)
            let expected = MockupFixture.png(width: 20, height: 30)

            try sut.saveMockup(first)
            try sut.saveMockup(expected)
            let actual = sut.loadMockup()

            #expect(actual == expected)
        }

        @Test("Removing the mockup leaves none to load; removing when there is none is no error")
        func remove() throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let sut = MockupFolder(directory: directory)
            try sut.saveMockup(MockupFixture.png(width: 4, height: 4))

            sut.removeMockup()
            sut.removeMockup()

            #expect(sut.loadMockup() == nil)
        }

        @Test("An empty folder, or one that doesn't exist, has no mockup and no settings")
        func empty() {
            let sut = MockupFolder(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))

            #expect(sut.loadMockup() == nil)
            #expect(sut.loadSettings() == nil)
        }

        @Test("Saved settings read back as saved")
        func settings() {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let sut = MockupFolder(directory: directory)
            var expected = DesignOverlaySettings()
            expected.opacity = 0.3
            expected.offset = CGSize(width: 4, height: -2)
            expected.blend = .difference
            expected.scale = .fitWidth

            sut.saveSettings(expected)
            let actual = sut.loadSettings()

            #expect(actual == expected)
        }

        @Test("Settings that aren't JSON of settings read as none")
        func corruptSettings() throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("{\"opacity\": \"half\"}".utf8).write(to: directory.appending(path: "Settings.json"))
            let sut = MockupFolder(directory: directory)

            let actual = sut.loadSettings()

            #expect(actual == nil)
        }

        @Test("A folder that can't be created throws notSaved")
        func unwritable() throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            // A file where the folder's parent would be.
            try Data("file".utf8).write(to: directory)
            let sut = MockupFolder(directory: directory.appending(path: "DesignOverlay"))

            #expect(throws: MockupFailure.notSaved) { try sut.saveMockup(MockupFixture.png(width: 2, height: 2)) }
        }
    }
#endif
