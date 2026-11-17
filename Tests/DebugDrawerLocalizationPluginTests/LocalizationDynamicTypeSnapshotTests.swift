// iOS scales text with Dynamic Type, so the large-text snapshots run on the iOS simulator.
#if os(iOS)
    @testable import DebugDrawerLocalizationPlugin
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct LocalizationDynamicTypeSnapshotTests {
        @Test("The plugin stays readable at an accessibility text size: switches below their titles, keys cut in the middle, buttons stacked")
        func missing() throws {
            let bundle = LocalizedBundle(
                name: "DebugDrawerExample.app", path: "/App.app", isMain: true, developmentLocalization: "en", preferredLocalization: "de",
                tables: [
                    "en": [LocalizationTable(name: "Localizable", entries: [
                        "welcome.title": LocalizationEntry("Welcome back"),
                        "settings.privacy": LocalizationEntry("Privacy Policy"),
                        "checkout.promo": LocalizationEntry("Have a promo code?")
                    ])],
                    "de": [LocalizationTable(name: "Localizable", entries: ["welcome.title": LocalizationEntry("Willkommen zurück")])]
                ]
            )
            let sut = LocalizationView(mode: .constant(.pseudoLocalized), bundles: [bundle], lookups: [], onRefresh: {})
                .environment(\.locale, Locale(identifier: "en_US"))
                .frame(width: 320, alignment: .leading)
                // No height proposed, as the drawer's scroll view proposes none: offered the
                // window's height, the list's scroll view would grow to its tallest.
                .fixedSize(horizontal: false, vertical: true)
                .padding()
                .background(Color(uiColor: .systemBackground))
                .environment(\.dynamicTypeSize, .accessibility3)
            // ImageRenderer draws UIKit-backed controls (the switches, the field, the buttons) as
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
