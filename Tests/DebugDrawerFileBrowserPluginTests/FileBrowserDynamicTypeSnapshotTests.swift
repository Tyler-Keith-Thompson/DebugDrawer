// iOS scales text with Dynamic Type, so the large-text snapshots run on the iOS simulator.
#if os(iOS)
    import SnapshotTesting
    import SwiftUI
    import Testing
    @testable import DebugDrawerFileBrowserPlugin

    // ImageRenderer draws the view without a window, at a fixed scale and width, so the
    // reference doesn't depend on which simulator runs it.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct FileBrowserDynamicTypeSnapshotTests {
        @Test("File rows stay readable at a large accessibility text size")
        func rows() throws {
            let notes = FSNode(
                name: "notes.txt", path: "/tmp/Example/Documents/notes.txt", isDirectory: false,
                size: 2_048, modified: nil, children: nil
            )
            let nodes = [
                FSNode(
                    name: "Documents", path: "/tmp/Example/Documents", isDirectory: true,
                    size: 0, modified: nil, children: [notes]
                ),
                FSNode(
                    name: "photo.png", path: "/tmp/Example/photo.png", isDirectory: false,
                    size: 3_145_728, modified: nil, children: nil
                ),
                FSNode(
                    name: "settings.plist", path: "/tmp/Example/settings.plist", isDirectory: false,
                    size: 640, modified: nil, children: nil
                )
            ]
            let sut = VStack(alignment: .leading, spacing: 0) {
                ForEach(nodes) { node in
                    FileRow(node: node, depth: 0, onDelete: { _ in }, onShare: { _ in })
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
