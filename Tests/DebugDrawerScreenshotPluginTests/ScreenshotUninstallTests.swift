#if DEBUG
    @testable import DebugDrawer
    @testable import DebugDrawerScreenshotPlugin
    import Foundation
    import Testing

    @MainActor
    @Suite("Screenshot drops its last capture once removed from every drawer")
    struct ScreenshotUninstallTests {
        private static func drawer() throws -> (DebugDrawer, () -> Void) {
            let suite = "ScreenshotUninstallTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            return (DebugDrawer(defaults: defaults), { defaults.removePersistentDomain(forName: suite) })
        }

        @Test("Unregistering removes the plugin and drops the last capture and its result, keeping whether to hide the drawer")
        func disappearsFromTheDrawer() throws {
            let (drawer, cleanUp) = try Self.drawer()
            defer { cleanUp() }
            let store = ScreenshotStore()
            let sut = ScreenshotPlugin(store: store)
            drawer.registerGlobal(sut)
            store.lastCapture = PlatformImage()
            store.lastPath = "Copied to clipboard"
            store.hideDrawer = false
            #if os(macOS)
                store.refusedCapture = PNGDocument(data: Data([0x89, 0x50, 0x4E, 0x47]))
                store.refusedFilename = "capture.png"
            #endif

            drawer.unregisterGlobal(id: sut.id)

            #expect(!drawer.globalPlugins.contains { $0.id == sut.id })
            #expect(store.lastCapture == nil)
            #expect(store.lastPath == nil)
            #expect(!store.hideDrawer)
            #if os(macOS)
                #expect(store.refusedCapture == nil)
                #expect(store.refusedFilename.isEmpty)
            #endif
        }

        @Test("A second drawer still holding the plugin keeps the last capture")
        func twoDrawers() throws {
            let (first, cleanUpFirst) = try Self.drawer()
            let (second, cleanUpSecond) = try Self.drawer()
            defer {
                cleanUpFirst()
                cleanUpSecond()
            }
            let store = ScreenshotStore()
            let sut = ScreenshotPlugin(store: store)
            first.registerGlobal(sut)
            second.registerGlobal(sut)
            store.lastPath = "Copied to clipboard"

            first.unregisterGlobal(id: sut.id)
            let whileTheSecondHoldsIt = store.lastPath
            sut.uninstall(from: first)
            second.unregisterGlobal(id: sut.id)

            #expect(whileTheSecondHoldsIt == "Copied to clipboard")
            #expect(store.lastPath == nil)
        }
    }
#endif
