// iOS scales text with Dynamic Type, so the large-text snapshots run on the iOS simulator.
#if os(iOS)
    @testable import DebugDrawer
    @testable import DebugDrawerNetworkPlugin
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    // The header row as the drawer draws it, at the width of the drawer on an iPad, the narrowest
    // it gets. It is hosted in a window that is never shown and its layer rendered, at a fixed
    // width and scale, as the other iOS snapshots are.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct NetworkHeaderRowDynamicTypeSnapshotTests {
        @Test(
            "In an iPad's drawer, the Network header keeps its title and triangle, with its failures, conditions, mocks and requests under it",
            arguments: [DynamicTypeSize.large, .accessibility3]
        )
        func narrowHeader(size: DynamicTypeSize) throws {
            let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
            let entries = [
                NetworkEntry(timestamp: start, method: "GET", url: "", host: "", path: "", requestHeaders: [:], requestBody: nil,
                             statusCode: 200, isComplete: true),
                NetworkEntry(timestamp: start, method: "GET", url: "", host: "", path: "", requestHeaders: [:], requestBody: nil,
                             error: "Timed out", isComplete: true)
            ]
            let conditions = [
                NetworkConditionProfile(name: "Slow example.com", host: .exact("example.com"), latency: .seconds(2)),
                NetworkConditionProfile(name: "Greeting offline", failureRate: 100, failure: .notConnectedToInternet)
            ]
            let plugin = AnyDebugDrawerPlugin(HeaderFixturePlugin(entries: entries, activeMocks: 2, conditions: conditions))
            let sut = DrawerPluginSection(plugin: plugin, isExpanded: false) {
                PluginSectionHeader(plugin: plugin, isExpanded: false, isPinned: false, badge: nil, isMovable: false) {}
            }
            .environment(\.locale, Locale(identifier: "en_US"))
            .frame(width: 316)
            // No height proposed, as the drawer's scroll view proposes none.
            .fixedSize(horizontal: false, vertical: true)
            .background(Color(uiColor: .systemBackground))
            .environment(\.dynamicTypeSize, size)
            let controller = UIHostingController(rootView: sut)
            // No safe area: the window's status bar inset would lay the view out shorter than it
            // measured.
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

    /// The Network plugin's header with fixed values in place of the shared store and models.
    private struct HeaderFixturePlugin: DebugDrawerPlugin {
        let title = "Network"
        let icon = "network"
        let entries: [NetworkEntry]
        let activeMocks: Int
        let conditions: [NetworkConditionProfile]
        var body: some View { EmptyView() }
        var headerAccessory: some View {
            NetworkHeaderSummary(entries: entries, activeMocks: activeMocks, conditions: conditions)
        }
    }
#endif
