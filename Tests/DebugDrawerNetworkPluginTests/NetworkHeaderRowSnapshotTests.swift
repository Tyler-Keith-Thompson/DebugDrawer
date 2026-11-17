// Views render on the Mac; the snapshot packages are linked on Apple platforms only.
#if os(macOS)
    @testable import DebugDrawer
    @testable import DebugDrawerNetworkPlugin
    import SnapshotTesting
    import SwiftUI
    import Testing

    // The header row as the drawer draws it, at the width of the drawer on an iPad, the narrowest
    // it gets, so a header accessory too wide to share the row shows up as the row it breaks.
    // macOS doesn't scale text with Dynamic Type, so the Mac pins light and dark only.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct NetworkHeaderRowSnapshotTests {
        @Test(
            "In a narrow drawer, the Network header keeps its title and triangle, and its failures, conditions, mocks and requests go under it",
            arguments: [ColorScheme.light, .dark]
        )
        func narrowHeader(colorScheme: ColorScheme) throws {
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
            let renderer = ImageRenderer(content: sut
                .environment(\.locale, Locale(identifier: "en_US"))
                .frame(width: 316)
                .background(.background)
                .environment(\.colorScheme, colorScheme))
            renderer.scale = 2

            let actual = try #require(renderer.nsImage)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "\(colorScheme)")
        }

        @Test("In a wide drawer, the Network header's accessory stays beside the title", arguments: [ColorScheme.light, .dark])
        func wideHeader(colorScheme: ColorScheme) throws {
            let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
            let entries = [
                NetworkEntry(timestamp: start, method: "GET", url: "", host: "", path: "", requestHeaders: [:], requestBody: nil,
                             statusCode: 200, isComplete: true)
            ]
            let conditions = [NetworkConditionProfile(name: "3G", latency: .milliseconds(100), bandwidth: 97500)]
            let plugin = AnyDebugDrawerPlugin(HeaderFixturePlugin(entries: entries, activeMocks: 0, conditions: conditions))
            let sut = DrawerPluginSection(plugin: plugin, isExpanded: false) {
                PluginSectionHeader(plugin: plugin, isExpanded: false, isPinned: false, badge: nil, isMovable: false) {}
            }
            let renderer = ImageRenderer(content: sut
                .environment(\.locale, Locale(identifier: "en_US"))
                .frame(width: 420)
                .background(.background)
                .environment(\.colorScheme, colorScheme))
            renderer.scale = 2

            let actual = try #require(renderer.nsImage)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "\(colorScheme)")
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
