// iOS scales text with Dynamic Type, so the large-text snapshots run on the iOS simulator.
#if os(iOS) && !targetEnvironment(macCatalyst)
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit
    @testable import DebugDrawerNetworkPlugin

    // ImageRenderer draws UIKit-backed controls (text fields, pickers, switches) as placeholders,
    // so each view is hosted in a window that is never shown and its layer rendered, at a fixed
    // width and scale, so the reference doesn't depend on which simulator runs it.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct NetworkDynamicTypeSnapshotTests {
        @Test("Request rows stay readable at a large accessibility text size")
        func rows() throws {
            let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
            let entries = [
                NetworkEntry(
                    timestamp: start, method: "GET", url: "https://api.example.com/v1/users?page=2",
                    host: "api.example.com", path: "/v1/users", requestHeaders: [:], requestBody: nil,
                    statusCode: 200, duration: 0.142, isComplete: true
                ),
                NetworkEntry(
                    timestamp: start, method: "POST", url: "https://api.example.com/v1/orders",
                    host: "api.example.com", path: "/v1/orders", requestHeaders: [:], requestBody: nil,
                    statusCode: 422, duration: 1.25, isComplete: true
                ),
                NetworkEntry(
                    timestamp: start, method: "DELETE", url: "https://api.example.com/v1/orders/7",
                    host: "api.example.com", path: "/v1/orders/7", requestHeaders: [:], requestBody: nil,
                    duration: 0.05, error: "The network connection was lost.", isComplete: true
                )
            ]
            let sut = VStack(spacing: 0) {
                ForEach(entries) { entry in
                    NetworkRequestRow(entry: entry, redaction: .standard, isSelected: false, onSelect: {})
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

        @Test("A selected request stays readable at a large accessibility text size")
        func selectedRow() throws {
            let metrics = NetworkTimingMetrics(
                phases: [
                    .init(kind: .dns, start: 0, duration: 0.012),
                    .init(kind: .connect, start: 0.012, duration: 0.03),
                    .init(kind: .tls, start: 0.02, duration: 0.022),
                    .init(kind: .request, start: 0.042, duration: 0.001),
                    .init(kind: .timeToFirstByte, start: 0.043, duration: 0.08),
                    .init(kind: .response, start: 0.123, duration: 0.019)
                ],
                protocolName: "h2", isReusedConnection: false, isCacheHit: false
            )

            let entry = NetworkEntry(
                timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000), method: "GET",
                url: "https://api.example.com/v1/users?page=2", host: "api.example.com", path: "/v1/users",
                requestHeaders: ["Accept": "application/json"], requestBody: nil,
                statusCode: 200, responseHeaders: ["Content-Type": "application/json"],
                responseBody: Data(#"{"users":[{"name":"Ada"}]}"#.utf8), duration: 0.142, isComplete: true,
                metrics: metrics
            )
            let sut = NetworkRequestRow(entry: entry, redaction: .standard, isSelected: true, onSelect: {})
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

        @Test("The timing gauges stay readable at a large accessibility text size")
        func timing() throws {
            let metrics = NetworkTimingMetrics(
                phases: [
                    .init(kind: .dns, start: 0, duration: 0.012),
                    .init(kind: .connect, start: 0.012, duration: 0.03),
                    .init(kind: .tls, start: 0.02, duration: 0.022),
                    .init(kind: .request, start: 0.042, duration: 0.001),
                    .init(kind: .timeToFirstByte, start: 0.043, duration: 0.08),
                    .init(kind: .response, start: 0.123, duration: 0.019)
                ],
                protocolName: "h2", isReusedConnection: false, isCacheHit: false
            )

            let sut = NetworkTimingView(metrics: metrics)
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
