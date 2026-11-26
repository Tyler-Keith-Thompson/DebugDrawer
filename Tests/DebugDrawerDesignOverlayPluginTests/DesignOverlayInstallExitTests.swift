// Installing registers the plugin with the drawer of the process that runs it and fills the shared
// model, so these run in a child process each, in a file of their own, as exit tests need one. The
// README's example is here, verbatim, rather than in DebugDrawerTests, which links core alone.
#if os(macOS) && DEBUG
    import AppKit
    @testable import DebugDrawer
    @testable import DebugDrawerDesignOverlayPlugin
    import Foundation
    import ImageIO
    import SwiftUI
    import Testing
    import UniformTypeIdentifiers

    struct ContentView: View {
        var body: some View {
            Text("Checkout")
        }
    }

    // The README's example, verbatim.
    struct ShopApp: App {
        init() {
            // At startup:
            DesignOverlay.install()
        }

        var body: some Scene {
            WindowGroup {
                ContentView()
                    .debugDesignOverlay() // beneath .debugDrawer(), so the mockup lies under the drawer
                    .debugDrawer()
            }
        }
    }

    @Suite("Design Overlay install, in a child process")
    struct DesignOverlayInstallExitTests {
        @Test("Install registers the plugin, with a HUD readout, in the Interface category")
        func install() async throws {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                let isExpected = await MainActor.run {
                    DesignOverlay.install()
                    let plugin = DebugDrawer.shared.globalPlugins.first { $0.title == "Design Overlay" }
                    return plugin?.hasHUD == true && plugin?.category == "Interface"
                }
                exit(isExpected ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        @Test("Installing again registers the plugin once over the one model, and a mockup handed to install shows without being saved")
        func installAgainWithMockup() async {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                let isExpected = await MainActor.run {
                    let storage = FakeMockupStorage()
                    let model = DesignOverlayModel(storage: storage)
                    DesignOverlayInstallation.install(model: model)
                    _ = try? DesignOverlayInstallation.install(mockup: MockupFixture.png(width: 64, height: 32), model: model)
                    let plugins = DebugDrawer.shared.globalPlugins.count { $0.title == "Design Overlay" }
                    return plugins == 1 && model.mockup?.pixelSize == CGSize(width: 64, height: 32) && storage.mockup == nil
                }
                exit(isExpected ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        @Test("README: Design Overlay")
        func readme() async {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                let isInstalled = await MainActor.run {
                    _ = ShopApp()
                    return DebugDrawer.shared.globalPlugins.count { $0.title == "Design Overlay" } == 1
                }
                exit(isInstalled ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }
    }
#endif
