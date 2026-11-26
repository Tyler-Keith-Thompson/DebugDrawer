#if DEBUG
    import DebugDrawer
    @testable import DebugDrawerDesignOverlayPlugin
    import Foundation
    import Testing

    // In-process: data that isn't an image is refused before the installer touches the shared
    // drawer or reads a file, so nothing here changes the process.
    @MainActor
    @Suite
    struct DesignOverlayInstallValidationTests {
        @Test("Installing with data that isn't an image throws NotAnImage and registers nothing")
        func notAnImage() {
            let storage = FakeMockupStorage()
            let model = DesignOverlayModel(storage: storage)
            let data = Data("not an image".utf8)

            #expect(throws: DesignOverlay.NotAnImage.self) {
                try DesignOverlayInstallation.install(mockup: data, model: model)
            }
            #expect(model.mockup == nil)
            #expect(!DebugDrawer.shared.globalPlugins.contains { $0.title == "Design Overlay" })
        }

        @Test("Installing with empty data throws NotAnImage")
        func emptyData() {
            let model = DesignOverlayModel(storage: FakeMockupStorage())

            #expect(throws: DesignOverlay.NotAnImage.self) {
                try DesignOverlayInstallation.install(mockup: Data(), model: model)
            }
        }
    }
#endif
