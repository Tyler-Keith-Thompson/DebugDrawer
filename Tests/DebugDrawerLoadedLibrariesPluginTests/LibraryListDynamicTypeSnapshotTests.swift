// iOS scales text with Dynamic Type, so the large-text snapshots run on the iOS simulator.
#if os(iOS) && !targetEnvironment(macCatalyst)
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit
    @testable import DebugDrawerLoadedLibrariesPlugin

    // The list of libraries at the drawer's width on an iPad, hosted in a window that is never
    // shown and its layer rendered, at a fixed width and scale, so the reference doesn't depend on
    // which simulator runs it.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct LibraryListDynamicTypeSnapshotTests {
        @Test(
            "In an iPad's drawer, the list of libraries grows with the text size, so it holds as many libraries at a large accessibility size",
            arguments: [DynamicTypeSize.large, .accessibility3]
        )
        func libraries(size: DynamicTypeSize) {
            let libraries = (UInt32(0) ..< 20).map { index in
                LoadedLibrary(
                    id: index, name: "Library\(index)",
                    path: "/Applications/Example.app/Frameworks/Library\(index).framework/Library\(index)",
                    category: index < 10 ? .thirdParty : .system,
                    uuid: UUID(uuidString: String(format: "6F1E2D3C-4B5A-4978-8695-A4B3C2D1E0%02X", index)),
                    loadAddress: 0x1_0000_0000 + UInt(index) * 0x8000, version: nil
                )
            }
            let sut = LoadedLibraryList(libraries: libraries)
            let controller = UIHostingController(rootView: sut
                .frame(width: 316, alignment: .leading)
                // No height proposed, as the drawer's scroll view proposes none.
                .fixedSize(horizontal: false, vertical: true)
                .padding()
                .background(.background)
                .environment(\.dynamicTypeSize, size))
            // No safe area: the window's status bar inset would lay the view out shorter than it
            // measured, overlapping its rows.
            controller.safeAreaRegions = []
            let measured = controller.sizeThatFits(in: CGSize(width: 348, height: 8000))
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

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: size == .large ? "large" : "accessibility3")
        }
    }
#endif
