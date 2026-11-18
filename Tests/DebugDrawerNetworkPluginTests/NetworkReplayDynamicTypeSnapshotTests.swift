// iOS scales text with Dynamic Type, so the large-text snapshots run on the iOS simulator.
#if os(iOS) && !targetEnvironment(macCatalyst)
    @testable import DebugDrawerNetworkPlugin
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    // At 316 points, the width of the drawer on an iPad and the narrowest it gets, at the default
    // text size and an accessibility one, so the detail's four actions and the badges are seen to
    // fit there. Each view is hosted in a window that is never shown and its layer rendered, at a
    // fixed width and scale, as the other iOS snapshots are, since ImageRenderer draws UIKit-backed
    // controls as placeholders.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct NetworkReplayDynamicTypeSnapshotTests {
        @Test(
            "In an iPad's drawer, a replay's row keeps its badges and path, and its detail's link and actions wrap without squeezing",
            arguments: [DynamicTypeSize.large, .accessibility3]
        )
        func replayRow(size: DynamicTypeSize) {
            let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
            let original = NetworkEntry(
                timestamp: start, method: "GET", url: "https://api.example.com/v1/greeting/ada", host: "api.example.com",
                path: "/v1/greeting/ada", requestHeaders: [:], requestBody: nil, statusCode: 200, duration: 0.12, isComplete: true
            )
            let replay = NetworkEntry(
                timestamp: start + 42, method: "GET", url: original.url, host: original.host, path: original.path,
                requestHeaders: [:], requestBody: nil, statusCode: 200, responseHeaders: ["Content-Type": "application/json"],
                responseBody: Data(#"{"message":"Hello"}"#.utf8), duration: 0.0004, isComplete: true, mockRuleName: "Greeting",
                replayOf: original.id
            )
            let sut = NetworkRequestRow(
                entry: replay, redaction: .standard, isSelected: true, onSelect: {}, onMock: { _ in }, onResend: { _ in },
                onEditAndResend: { _ in }, onShow: { _ in }, links: NetworkReplayLinks(of: replay, in: [replay, original])
            )
            .environment(\.locale, Locale(identifier: "en_US"))
            .environment(\.timeZone, TimeZone(identifier: "UTC") ?? .gmt)

            let controller = UIHostingController(rootView: sut
                .frame(width: 316, alignment: .leading)
                // No height proposed, as the drawer's scroll view proposes none.
                .fixedSize(horizontal: false, vertical: true)
                .background(Color(uiColor: .systemBackground))
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
            "In an iPad's drawer, the question before a POST is resent keeps Send and Cancel whole",
            arguments: [DynamicTypeSize.large, .accessibility3]
        )
        func confirmation(size: DynamicTypeSize) {
            let original = NetworkEntry(
                timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000), method: "POST", url: "https://api.example.com/v1/orders",
                host: "api.example.com", path: "/v1/orders", requestHeaders: [:], requestBody: nil, statusCode: 201, duration: 0.18,
                isComplete: true
            )
            let sut = NetworkRequestDetail(
                entry: original, redaction: .standard, onMock: { _ in }, onResend: { _ in }, onEditAndResend: { _ in }, isConfirming: true
            )
            .environment(\.locale, Locale(identifier: "en_US"))

            let controller = UIHostingController(rootView: sut
                .frame(width: 316, alignment: .leading)
                // No height proposed, as the drawer's scroll view proposes none.
                .fixedSize(horizontal: false, vertical: true)
                .background(Color(uiColor: .systemBackground))
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
            "In an iPad's drawer, Edit and Resend keeps every field readable: each header's name above its value at a large size",
            arguments: [DynamicTypeSize.large, .accessibility3]
        )
        func replayEditor(size: DynamicTypeSize) {
            let entry = NetworkEntry(
                timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000), method: "POST", url: "https://api.example.com/v1/orders",
                host: "api.example.com", path: "/v1/orders", requestHeaders: ["Content-Type": "application/json"],
                requestBody: Data(#"{"item":"tea"}"#.utf8), statusCode: 201, isComplete: true
            )
            let sut = NetworkReplayEditor(draft: NetworkReplayDraft(entry), cancel: {}, send: { _ in })
                .environment(\.locale, Locale(identifier: "en_US"))

            let controller = UIHostingController(rootView: sut
                .frame(width: 316, alignment: .leading)
                // No height proposed, as the drawer's scroll view proposes none.
                .fixedSize(horizontal: false, vertical: true)
                .background(Color(uiColor: .systemBackground))
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
            "In an iPad's drawer, a request whose body the log cut short says why Resend is unavailable, under the actions",
            arguments: [DynamicTypeSize.large, .accessibility3]
        )
        func resendUnavailable(size: DynamicTypeSize) {
            let entry = NetworkEntry(
                timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000), method: "POST", url: "https://api.example.com/v1/upload",
                host: "api.example.com", path: "/v1/upload", requestHeaders: [:], requestBody: Data(repeating: 0x61, count: 1024),
                requestBodySize: 4096, statusCode: 201, duration: 0.18, isComplete: true
            )
            let sut = NetworkRequestDetail(entry: entry, redaction: .standard, onMock: { _ in }, onResend: { _ in }, onEditAndResend: { _ in })
                .environment(\.locale, Locale(identifier: "en_US"))

            let controller = UIHostingController(rootView: sut
                .frame(width: 316, alignment: .leading)
                // No height proposed, as the drawer's scroll view proposes none.
                .fixedSize(horizontal: false, vertical: true)
                .background(Color(uiColor: .systemBackground))
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
            "In an iPad's drawer, Edit and Resend of a body the log cut short keeps its note, Edit Kept Part and Remove Body readable",
            arguments: [DynamicTypeSize.large, .accessibility3]
        )
        func editorTruncatedBody(size: DynamicTypeSize) {
            let entry = NetworkEntry(
                timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000), method: "POST", url: "https://api.example.com/v1/upload",
                host: "api.example.com", path: "/v1/upload", requestHeaders: ["Content-Type": "application/json"],
                requestBody: Data(String(repeating: "a", count: 1024).utf8), requestBodySize: 4096, statusCode: 201, isComplete: true
            )
            let sut = NetworkReplayEditor(draft: NetworkReplayDraft(entry), cancel: {}, send: { _ in })
                .environment(\.locale, Locale(identifier: "en_US"))

            let controller = UIHostingController(rootView: sut
                .frame(width: 316, alignment: .leading)
                // No height proposed, as the drawer's scroll view proposes none.
                .fixedSize(horizontal: false, vertical: true)
                .background(Color(uiColor: .systemBackground))
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
