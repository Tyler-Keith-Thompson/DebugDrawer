// iOS scales text with Dynamic Type, so the large-text snapshots run on the iOS simulator.
#if os(iOS) && !targetEnvironment(macCatalyst)
    import DebugDrawer
    @testable import DebugDrawerDiskIOPlugin
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    // The list of calls at the drawer's width on an iPad, hosted in a window that is never shown
    // and its layer rendered, at a fixed width and scale, so the reference doesn't depend on which
    // simulator runs it.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct DiskIOCallListDynamicTypeSnapshotTests {
        @Test(
            "In an iPad's drawer, the list of calls grows with the text size, so it holds as many calls at a large accessibility size",
            arguments: [DynamicTypeSize.large, .accessibility3]
        )
        func calls(size: DynamicTypeSize) {
            let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
            let operations: [IOEvent.Operation] = [.read, .write, .create, .delete]
            let events = (0 ..< 20).map { index in
                IOEvent(
                    timestamp: start.addingTimeInterval(Double(index)), operation: operations[index % operations.count],
                    path: "/Users/ada/Library/Caches/Example/item-\(index).json",
                    size: Int64(1_024 * (index + 1)), duration: 0.001, isMainThread: index.isMultiple(of: 4)
                )
            }
            let sut = DiskIOCallList(events: events)
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
