// iOS scales text with Dynamic Type, so the large-text snapshots run on the iOS simulator.
#if os(iOS) && !targetEnvironment(macCatalyst)
    @testable import DebugDrawerDeepLinkPlugin
    import Foundation
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    // At 316 points, the width of the drawer on an iPad and the narrowest it gets, at the default
    // text size and an accessibility one, so each state is seen to fit there. Each view is hosted
    // in a window that is never shown and its layer rendered, at a fixed width and scale, as the
    // other iOS snapshots are.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct DeepLinkDynamicTypeSnapshotTests {
        // The share of pixels a hosted text-field snapshot must match: a hosted text field draws a
        // few pixels differently from run to run (DD-182).
        private static let textFieldPrecision: Float = 0.99

        @Test(
            "In an iPad's drawer: with no URL typed and no history, the form shows the mode picker, the field, a disabled Open and the presets",
            arguments: [DynamicTypeSize.large, .accessibility3]
        )
        func empty(size: DynamicTypeSize) throws {
            let presets: [DeepLinkPreset] = [
                try DeepLinkPreset("HTTPS", url: #require(URL(string: "https://example.com/path"))),
                try DeepLinkPreset("Custom Scheme", url: #require(URL(string: "myapp://deeplink/screen"))),
                try DeepLinkPreset("Mail", url: #require(URL(string: "mailto:test@example.com")))
            ]
            let sut = DeepLinkForm(urlText: .constant(""), presets: presets, onOpen: { _ in }, onContinue: { _ in }, onClear: {})

            let controller = UIHostingController(rootView: sut
                .frame(width: 316, alignment: .leading)
                // No height proposed, as the drawer's scroll view proposes none.
                .fixedSize(horizontal: false, vertical: true)
                .background(Color(uiColor: .systemBackground))
                .environment(\.locale, Locale(identifier: "en_US"))
                .environment(\.dynamicTypeSize, size))
            // No safe area: the window's status bar inset would lay the view out shorter than it
            // measured, overlapping its rows.
            controller.safeAreaRegions = []
            let measured = controller.sizeThatFits(in: CGSize(width: 316, height: 8000))
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

            // A hosted text field draws a few pixels differently from run to run (DD-182).
            assertSnapshot(
                of: actual, as: .image(precision: Self.textFieldPrecision, perceptualPrecision: 0.98),
                named: size == .large ? "large" : "accessibility3"
            )
        }

        @Test(
            "In an iPad's drawer: after an open, the form shows the URL with an Open link, the result and the history",
            arguments: [DynamicTypeSize.large, .accessibility3]
        )
        func afterOpening(size: DynamicTypeSize) throws {
            let presets: [DeepLinkPreset] = [
                try DeepLinkPreset("HTTPS", url: #require(URL(string: "https://example.com/path"))),
                try DeepLinkPreset("Custom Scheme", url: #require(URL(string: "myapp://deeplink/screen")))
            ]
            let sut = DeepLinkForm(
                urlText: .constant("myapp://orders/42"),
                outcome: .opened("myapp://orders/42"),
                presets: presets,
                history: ["myapp://orders/42", "myapp://deeplink/screen"],
                onOpen: { _ in },
                onContinue: { _ in },
                onClear: {}
            )

            let controller = UIHostingController(rootView: sut
                .frame(width: 316, alignment: .leading)
                // No height proposed, as the drawer's scroll view proposes none.
                .fixedSize(horizontal: false, vertical: true)
                .background(Color(uiColor: .systemBackground))
                .environment(\.locale, Locale(identifier: "en_US"))
                .environment(\.dynamicTypeSize, size))
            // No safe area: the window's status bar inset would lay the view out shorter than it
            // measured, overlapping its rows.
            controller.safeAreaRegions = []
            let measured = controller.sizeThatFits(in: CGSize(width: 316, height: 8000))
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

            // A hosted text field draws a few pixels differently from run to run (DD-182).
            assertSnapshot(
                of: actual, as: .image(precision: Self.textFieldPrecision, perceptualPrecision: 0.98),
                named: size == .large ? "large" : "accessibility3"
            )
        }

        @Test(
            "In an iPad's drawer: after continuing an https URL, the form shows Universal Link, Continue, where it went and the activity history",
            arguments: [DynamicTypeSize.large, .accessibility3]
        )
        func universalLink(size: DynamicTypeSize) throws {
            let presets: [DeepLinkPreset] = [
                try DeepLinkPreset("HTTPS", url: #require(URL(string: "https://example.com/path"))),
                try DeepLinkPreset("Custom Scheme", url: #require(URL(string: "myapp://deeplink/screen")))
            ]
            let activities = [
                DeepLinkActivity(activityType: NSUserActivityTypeBrowsingWeb, webpageURL: URL(string: "https://example.com/orders/42"), userInfo: []),
                DeepLinkActivity(
                    activityType: "com.example.app.viewOrder", webpageURL: nil,
                    userInfo: [UserInfoEntry(key: "orderID", value: .integer(7)), UserInfoEntry(key: "gift", value: .bool(true))]
                )
            ]
            let sut = DeepLinkForm(
                urlText: .constant("https://example.com/orders/42"),
                outcome: .continued(.handler),
                presets: presets,
                history: ["myapp://orders/42"],
                activities: activities,
                onOpen: { _ in },
                onContinue: { _ in },
                onClear: {}
            )

            let controller = UIHostingController(rootView: sut
                .frame(width: 316, alignment: .leading)
                // No height proposed, as the drawer's scroll view proposes none.
                .fixedSize(horizontal: false, vertical: true)
                .background(Color(uiColor: .systemBackground))
                .environment(\.locale, Locale(identifier: "en_US"))
                .environment(\.dynamicTypeSize, size))
            // No safe area: the window's status bar inset would lay the view out shorter than it
            // measured, overlapping its rows.
            controller.safeAreaRegions = []
            let measured = controller.sizeThatFits(in: CGSize(width: 316, height: 8000))
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

            // A hosted text field draws a few pixels differently from run to run (DD-182).
            assertSnapshot(
                of: actual, as: .image(precision: Self.textFieldPrecision, perceptualPrecision: 0.98),
                named: size == .large ? "large" : "accessibility3"
            )
        }

        @Test(
            "In an iPad's drawer: in Activity mode with no handler, the form shows the type, a row of each userInfo type, Add Key and what to do",
            arguments: [DynamicTypeSize.large, .accessibility3]
        )
        func activity(size: DynamicTypeSize) throws {
            let draft = ActivityDraft(activityType: "com.example.app.viewOrder", fields: [
                UserInfoField(key: "orderID", kind: .number, text: "42"),
                UserInfoField(key: "title", kind: .string, text: "Ada's order"),
                UserInfoField(key: "gift", kind: .boolean, isOn: true)
            ])
            let sut = DeepLinkForm(
                urlText: .constant(""),
                outcome: .continued(.unhandled),
                presets: [],
                mode: .activity,
                draft: draft,
                onOpen: { _ in },
                onContinue: { _ in },
                onClear: {}
            )

            let controller = UIHostingController(rootView: sut
                .frame(width: 316, alignment: .leading)
                // No height proposed, as the drawer's scroll view proposes none.
                .fixedSize(horizontal: false, vertical: true)
                .background(Color(uiColor: .systemBackground))
                .environment(\.locale, Locale(identifier: "en_US"))
                .environment(\.dynamicTypeSize, size))
            // No safe area: the window's status bar inset would lay the view out shorter than it
            // measured, overlapping its rows.
            controller.safeAreaRegions = []
            let measured = controller.sizeThatFits(in: CGSize(width: 316, height: 8000))
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

            // A hosted text field draws a few pixels differently from run to run (DD-182).
            assertSnapshot(
                of: actual, as: .image(precision: Self.textFieldPrecision, perceptualPrecision: 0.98),
                named: size == .large ? "large" : "accessibility3"
            )
        }
    }
#endif
