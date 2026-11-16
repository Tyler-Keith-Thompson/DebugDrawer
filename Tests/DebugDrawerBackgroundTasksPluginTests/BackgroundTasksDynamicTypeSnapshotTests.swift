// iOS scales text with Dynamic Type, so the large-text snapshots run on the iOS simulator.
#if os(iOS)
    @testable import DebugDrawerBackgroundTasksPlugin
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct BackgroundTasksDynamicTypeSnapshotTests {
        @Test("The plugin stays readable at a large accessibility text size, the glyphs above the identifiers and the buttons stacked")
        func backgroundTasks() {
            let sut = BackgroundTasksView(
                declaration: BackgroundTaskDeclaration(
                    identifiers: [PermittedIdentifier("com.example.orders.refresh"), PermittedIdentifier("com.example.orders.cleanup")],
                    kinds: [.appRefresh, .processing]
                ),
                pending: .loaded([BackgroundTaskRequest(
                    id: "com.example.orders.refresh", earliestBeginDate: Date(timeIntervalSince1970: 1_800_000_000), kind: .appRefresh
                )]),
                schedule: .failed(identifier: "com.example.orders.cleanup", kind: .processing, failure: .notPermitted),
                actions: BackgroundTasksActions()
            )
            .frame(width: 320, alignment: .leading)
            .padding()
            .background(Color(uiColor: .systemBackground))
            .environment(\.dynamicTypeSize, .accessibility3)
            .environment(\.locale, Locale(identifier: "en_US_POSIX"))
            .environment(\.timeZone, TimeZone(identifier: "UTC") ?? .gmt)
            // ImageRenderer draws UIKit-backed controls (the buttons, the progress indicator) as
            // placeholders, so the view is hosted in a window that is never shown and its layer is
            // rendered, at a fixed width and scale.
            let controller = UIHostingController(rootView: sut)
            // No safe area: the window's status bar inset would lay the view out shorter than it
            // measured, overlapping its rows.
            controller.safeAreaRegions = []
            let size = controller.sizeThatFits(in: CGSize(width: 352, height: 6000))
            let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            let window = scene.map(UIWindow.init(windowScene:)) ?? UIWindow()
            window.frame = CGRect(origin: .zero, size: size)
            window.rootViewController = controller
            window.overrideUserInterfaceStyle = .light
            window.isHidden = false
            controller.view.frame = window.bounds
            window.layoutIfNeeded()
            let format = UIGraphicsImageRendererFormat()
            format.scale = 2
            let actual = UIGraphicsImageRenderer(size: size, format: format).image { context in
                controller.view.layer.render(in: context.cgContext)
            }
            window.isHidden = true

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "accessibility3")
        }
    }
#endif
