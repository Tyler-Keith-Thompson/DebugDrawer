// iOS scales text with Dynamic Type, so the large-text snapshots run on the iOS simulator.
#if os(iOS)
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit
    @testable import DebugDrawerLoadedLibrariesPlugin

    // ImageRenderer draws UIKit-backed controls (text fields, pickers, switches) as placeholders,
    // so each view is hosted in a window that is never shown and its layer rendered, at a fixed
    // width and scale, so the reference doesn't depend on which simulator runs it.
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
            let controller = UIHostingController(rootView: sut
                .frame(width: 320, alignment: .leading)
                // No height proposed, as the drawer's scroll view proposes none.
                .fixedSize(horizontal: false, vertical: true)
                .padding()
                .background(.background)
                .environment(\.dynamicTypeSize, .accessibility3))
            // No safe area: the window's status bar inset would lay the view out shorter than it
            // measured, overlapping its rows.
            controller.safeAreaRegions = []
            let measured = controller.sizeThatFits(in: CGSize(width: 352, height: 8000))
            let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            let window = scene.map(UIWindow.init(windowScene:)) ?? UIWindow()
            window.frame = CGRect(origin: .zero, size: measured)
            window.rootViewController = controller
            window.overrideUserInterfaceStyle = .light
            window.isHidden = false
            controller.view.frame = window.bounds
            window.layoutIfNeeded()
            let format = UIGraphicsImageRendererFormat()
            format.scale = 2

            let actual = UIGraphicsImageRenderer(size: measured, format: format).image { context in
                controller.view.layer.render(in: context.cgContext)
            }
            window.isHidden = true

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "accessibility3")
        }
    }
#endif
