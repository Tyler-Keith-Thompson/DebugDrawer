// iOS scales text with Dynamic Type, so the large-text snapshots run on the iOS simulator.
#if os(iOS)
    import DebugDrawer
    @testable import DebugDrawerNetworkPlugin
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    // At 316 points, the width of the drawer on an iPad and the narrowest it gets, at the default
    // text size and an accessibility one, so Export, Import HAR… and Clear are seen to fit, and the
    // imported request's actions to wrap. Each view is hosted in a window that is never shown and
    // its layer rendered, at a fixed width and scale, as the other iOS snapshots are, since
    // ImageRenderer draws UIKit-backed controls as placeholders.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct NetworkArchiveDynamicTypeSnapshotTests {
        @Test(
            "In an iPad's drawer, the import and export controls keep whole words, and a refused file says why",
            arguments: [DynamicTypeSize.large, .accessibility3]
        )
        func controls(size: DynamicTypeSize) {
            let entry = NetworkEntry(
                timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000), method: "GET", url: "https://shop.example.com/api/cart",
                host: "shop.example.com", path: "/api/cart", requestHeaders: [:], requestBody: nil, statusCode: 500, isComplete: true
            )
            let issue = NetworkImportIssue(fileName: "notes.json", error: .notAnArchive)
            let sut = VStack(alignment: .leading, spacing: 0) {
                NetworkLogSourcePicker(source: .constant(.imported), fileName: "shop.example.com.har", count: 12)
                NetworkToolbar(
                    filterStatus: .constant(.serverError), clear: {}, export: NetworkArchiveFile(entries: [entry], redaction: .standard),
                    isFiltered: true, importArchive: {}, source: .imported
                )
                DebugDrawerIssueRow("Not imported", severity: .error) {
                    Text(issue.message)
                }
            }
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
            "In an iPad's drawer, an imported request's row keeps its path, and its detail's Copy cURL and Mock This wrap without squeezing",
            arguments: [DynamicTypeSize.large, .accessibility3]
        )
        func importedRow(size: DynamicTypeSize) {
            let entry = NetworkEntry(
                timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000), method: "GET", url: "https://shop.example.com/api/cart?id=12",
                host: "shop.example.com", path: "/api/cart", requestHeaders: ["accept": "application/json"], requestBody: nil,
                statusCode: 200, responseHeaders: ["content-type": "application/json"], responseBody: Data(#"{"items":2}"#.utf8),
                duration: 0.048, isComplete: true
            )
            let sut = NetworkRequestRow(entry: entry, redaction: .standard, isSelected: true, onSelect: {}, onMock: { _ in }, onShow: { _ in })
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
