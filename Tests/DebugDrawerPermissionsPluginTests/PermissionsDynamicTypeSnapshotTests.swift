// iOS scales text with Dynamic Type, so the large-text snapshots run on the iOS simulator.
#if os(iOS) && !targetEnvironment(macCatalyst)
    @testable import DebugDrawerPermissionsPlugin
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct PermissionsDynamicTypeSnapshotTests {
        @Test("The permissions stay readable at a large accessibility text size, each status below its name and the buttons stacked")
        func permissions() {
            let rows = [
                PermissionRowState(
                    permission: DeclaredPermission(
                        kind: .camera, usageDescriptions: [UsageDescription(key: "NSCameraUsageDescription", text: "Scans receipts")]
                    ),
                    status: .denied, request: .unavailable
                ),
                PermissionRowState(
                    permission: DeclaredPermission(
                        kind: .location,
                        usageDescriptions: [UsageDescription(key: "NSLocationWhenInUseUsageDescription", text: "Shows nearby stores")]
                    ),
                    status: .notDetermined, request: .available
                ),
                PermissionRowState(
                    permission: DeclaredPermission(kind: .notifications, usageDescriptions: []), status: .provisional, request: .unavailable
                )
            ]
            let sut = PermissionsView(rows: rows, onRequest: { _ in }, onOpenSettings: { _ in })
                .frame(width: 320, alignment: .leading)
                .padding()
                .background(Color(uiColor: .systemBackground))
                .environment(\.dynamicTypeSize, .accessibility3)
            // ImageRenderer draws UIKit-backed controls (the buttons) as placeholders, so the view
            // is hosted in a window that is never shown and its layer is rendered, at a fixed width
            // and scale.
            let controller = UIHostingController(rootView: sut)
            // No safe area: the window's status bar inset would lay the view out shorter than it
            // measured, overlapping its rows.
            controller.safeAreaRegions = []
            let size = controller.sizeThatFits(in: CGSize(width: 352, height: 4000))
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
