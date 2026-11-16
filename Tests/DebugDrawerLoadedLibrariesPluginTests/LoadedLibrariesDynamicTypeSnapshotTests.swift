// iOS scales text with Dynamic Type, so the large-text snapshots run on the iOS simulator.
#if os(iOS)
    import SnapshotTesting
    import SwiftUI
    import Testing
    @testable import DebugDrawerLoadedLibrariesPlugin

    // ImageRenderer draws the view without a window, at a fixed scale and width, so the
    // reference doesn't depend on which simulator runs it.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct LoadedLibrariesDynamicTypeSnapshotTests {
        @Test("Library rows stay readable at a large accessibility text size")
        func rows() throws {
            let libraries = [
                LoadedLibrary(
                    id: 0, name: "Example", path: "/Applications/Example.app/Contents/MacOS/Example", category: .app,
                    uuid: UUID(uuidString: "6F1E2D3C-4B5A-4978-8695-A4B3C2D1E0F9"), loadAddress: 0x1_0000_0000, version: nil
                ),
                LoadedLibrary(
                    id: 1, name: "Charts",
                    path: "/Applications/Example.app/Contents/Frameworks/Charts.framework/Versions/A/Charts",
                    category: .thirdParty,
                    uuid: UUID(uuidString: "0A1B2C3D-4E5F-4061-8293-A4B5C6D7E8F9"), loadAddress: 0x1_0234_8000, version: "5.1.0"
                )
            ]
            let sut = VStack(alignment: .leading, spacing: 4) {
                ForEach(libraries) { library in
                    LoadedLibraryRow(library: library)
                }
            }
            let renderer = ImageRenderer(content: sut
                .frame(width: 320, alignment: .leading)
                .padding()
                .background(.background)
                .environment(\.dynamicTypeSize, .accessibility3))
            renderer.scale = 2

            let actual = try #require(renderer.uiImage)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "accessibility3")
        }
    }
#endif
