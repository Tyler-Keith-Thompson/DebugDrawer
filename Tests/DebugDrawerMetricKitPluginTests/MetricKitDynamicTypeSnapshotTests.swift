// iOS scales text with Dynamic Type, so the large-text snapshots run on the iOS simulator.
#if os(iOS)
    @testable import DebugDrawerMetricKitPlugin
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct MetricKitDynamicTypeSnapshotTests {
        @Test("The payloads stay readable at a large accessibility text size, the New tag below the kind and the buttons stacked")
        func payloads() throws {
            let opened = MetricKitPayload(
                id: UUID(), kind: .diagnostics, begin: Date(timeIntervalSince1970: 1_763_290_000), end: Date(timeIntervalSince1970: 1_763_290_000),
                received: Date(timeIntervalSince1970: 1_763_290_000),
                json: Data("""
                {
                  "hangDiagnostics": [{"diagnosticMetaData": {"appVersion": "1.2", "hangDuration": "2.1 sec", "osVersion": "iPhone OS 26.1"}}],
                  "timeStampBegin": "2025-11-16 10:46:40 +0000",
                  "timeStampEnd": "2025-11-16 10:46:40 +0000"
                }
                """.utf8),
                isSeen: false
            )
            let metrics = MetricKitPayload(
                id: UUID(), kind: .metrics, begin: Date(timeIntervalSince1970: 1_763_164_800), end: Date(timeIntervalSince1970: 1_763_251_200),
                received: Date(timeIntervalSince1970: 1_763_254_000),
                json: Data("""
                {
                  "appVersion": "1.2", "metaData": {"appBuildVersion": "34"},
                  "cpuMetrics": {}, "diskIOMetrics": {}, "memoryMetrics": {}, "applicationLaunchMetrics": {}
                }
                """.utf8),
                isSeen: true
            )
            let sut = MetricKitPayloadsView(
                payloads: [opened, metrics], expanded: .constant(opened.id),
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
