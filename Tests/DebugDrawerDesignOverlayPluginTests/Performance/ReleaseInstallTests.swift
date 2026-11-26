// The release stand-in. `--config=release` builds and runs only the performance targets, so this
// is where a test is compiled without DEBUG, as an app's release build is; in debug the file is
// empty, and DesignOverlayInstallExitTests checks the opposite.
#if !DEBUG
    import DebugDrawerDesignOverlayPlugin
    import Foundation
    import SwiftUI
    import Testing

    @Suite
    struct ReleaseInstallTests {
        @MainActor
        @Test("In release, install takes any data without decoding or trapping, and writes nothing to Caches")
        func installDoesNothing() throws {
            // The sandboxed folder, and the one a Mac app outside the sandbox uses.
            let bundleIdentifier = Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName
            let folders = [
                URL.cachesDirectory.appending(path: "DebugDrawer/DesignOverlay"),
                URL.cachesDirectory.appending(path: "\(bundleIdentifier)/DebugDrawer/DesignOverlay")
            ]
            let existed = folders.map { FileManager.default.fileExists(atPath: $0.path) }

            DesignOverlay.install()
            try DesignOverlay.install(mockup: Data("not an image".utf8))
            let actual = folders.map { FileManager.default.fileExists(atPath: $0.path) }

            #expect(actual == existed)
        }

        @MainActor
        @Test("In release, debugDesignOverlay returns the view as it is")
        func modifierIsTheView() {
            let content = Text("Checkout")

            let actual = content.debugDesignOverlay()

            #expect(type(of: actual) == Text.self)
        }
    }
#endif
