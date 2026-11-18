// iOS scales text with Dynamic Type, so the large-text snapshots run on the iOS simulator.
#if os(iOS) && !targetEnvironment(macCatalyst)
    @testable import DebugDrawerNetworkPlugin
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    // At 316 points, the width of the drawer on an iPad and the narrowest it gets, at the default
    // text size and an accessibility one, so a GraphQL request's row, the hint and the Ignored
    // hosts section are seen to fit there. Each view is hosted in a window that is never shown and
    // its layer rendered, at a fixed width and scale, as the other iOS snapshots are.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct NetworkIgnoreDynamicTypeSnapshotTests {
        @Test(
            "In an iPad's drawer, GraphQL rows keep the method, status, path, operation and time readable, the detail its actions",
            arguments: [DynamicTypeSize.large, .accessibility3]
        )
        func graphQLRequest(size: DynamicTypeSize) {
            let entry = NetworkEntry(
                timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000), method: "POST", url: "https://api.example.com/graphql",
                host: "api.example.com", path: "/graphql", requestHeaders: [:],
                requestBody: Data(#"{"operationName":"GetUser","variables":{"id":"1"}}"#.utf8), statusCode: 200, duration: 0.142,
                isComplete: true
            )
            let other = NetworkEntry(
                timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000), method: "POST", url: "https://api.example.com/v2/graphql",
                host: "api.example.com", path: "/v2/graphql", requestHeaders: [:],
                requestBody: Data(#"{"query":"mutation UpdateUserPreferences { a }"}"#.utf8), statusCode: 200, duration: 0.088,
                isComplete: true
            )
            let sut = VStack(alignment: .leading, spacing: 0) {
                NetworkRequestRow(entry: other, redaction: .standard, isSelected: false, onSelect: {})
                NetworkRequestRow(
                    entry: entry, redaction: .standard, isSelected: true, onSelect: {}, onMock: { _ in }, onResend: { _ in },
                    onEditAndResend: { _ in }, onIgnore: { _ in }
                )
            }

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

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: size == .large ? "large" : "accessibility3")
        }

        @Test("In an iPad's drawer, the hint keeps its count and Show readable", arguments: [DynamicTypeSize.large, .accessibility3])
        func hint(size: DynamicTypeSize) {
            let sut = VStack(alignment: .leading, spacing: 0) {
                NetworkIgnoredHint(count: 12, isShowing: false) {}
                NetworkIgnoredHint(count: 12, isShowing: true) {}
            }

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

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: size == .large ? "large" : "accessibility3")
        }

        @Test(
            "In an iPad's drawer, the Ignored hosts section keeps each domain, Remove, the field and its problem readable",
            arguments: [DynamicTypeSize.large, .accessibility3]
        )
        func section(size: DynamicTypeSize) throws {
            let domains = try ["analytics.example.net", "cdn.example.com", "10.0.0.1"].map { try NetworkIgnoredDomain(parsing: $0) }
            let sut = NetworkIgnoreListSection(
                domains: domains, issue: nil, add: { _ in }, remove: { _ in }, text: "*.example.com", problem: .wildcard
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

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: size == .large ? "large" : "accessibility3")
        }
    }
#endif
