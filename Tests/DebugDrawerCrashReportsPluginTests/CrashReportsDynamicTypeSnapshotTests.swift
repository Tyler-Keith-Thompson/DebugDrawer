// iOS scales text with Dynamic Type, so the large-text snapshots run on the iOS simulator.
#if os(iOS) && !targetEnvironment(macCatalyst)
    @testable import DebugDrawerCrashReportsPlugin
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct CrashReportsDynamicTypeSnapshotTests {
        @Test("The reports stay readable at a large accessibility text size, the New tag below the title")
        func reports() throws {
            let opened = CrashReport(
                id: UUID(), date: Date(timeIntervalSince1970: 1_763_290_000), title: "SIGTRAP",
                reason: "Trap: a Swift runtime failure, such as unwrapping nil or an index out of range", appVersion: "1.2 (34)",
                frames: [
                    "0 libswiftCore.dylib 0x000000018f2b1a40 $ss17_assertionFailure__4file4line5flagss5NeverOs12StaticStringV_A2HSus6UInt32VtF + 172",
                    "1   Example              0x0000000100004a1c $s7Example11ContentViewV5crashyyF + 48"
                ],
                source: .captured, isSeen: false
            )
            let older = CrashReport(
                id: UUID(), date: Date(timeIntervalSince1970: 1_763_200_000), title: "SIGSEGV",
                reason: "Segmentation fault: an access to memory the app doesn't own", appVersion: "1.2 (33)",
                frames: [], source: .metricKit, isSeen: true
            )
            let sut = CrashReportsView(
                reports: [opened, older], expanded: .constant(opened.id), ownImage: "Example",
                onOpen: { _ in }, onDelete: { _ in }, onMarkAllSeen: {}, onDeleteAll: {}
            )
            .environment(\.locale, Locale(identifier: "en_US"))
            .environment(\.timeZone, try #require(TimeZone(identifier: "UTC")))
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
