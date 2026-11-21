#if DEBUG && os(watchOS)
    import DebugDrawer
    @testable import DebugDrawerSidecarKit
    import Foundation
    import SwiftUI
    import Testing
    import ViewInspector

    /// A model's snapshot, for a plugin the sidecar shows.
    private struct LevelSnapshot: Codable, Equatable, Sendable {
        var level = "info"
    }

    /// A model's commands, for a plugin the sidecar shows.
    private enum LevelCommand: Codable, Sendable {
        case reset
    }

    /// A plugin made over the transport, drawing the level.
    private struct LevelPlugin: DebugDrawerPlugin {
        let transport: DebugDrawerPluginTransport<LevelSnapshot, LevelCommand>
        let title = "Log Level"
        let icon = "slider.horizontal.3"

        var body: some View {
            Text(transport.snapshot.level)
        }
    }

    // The README's watch sidecar ("The sidecar on Apple TV, Vision Pro, Apple Watch and Mac
    // Catalyst"), verbatim but for `@main`, so it keeps compiling for watchOS.
    struct CompanyWatchSidecar: App {
        var body: some Scene {
            WindowGroup {
                DebugDrawerSidecarView(
                    groupIdentifier: "group.com.example.debug",
                    plugins: [.appState, .bugReports, .environments, .userDefaults]
                )
            }
        }
    }

    // The kit's watch layout (DD-261), the watch's navigation model as the drawer's: each app a row
    // that pushes it, and on an app's screen each plugin a row that pushes it, where the bigger
    // screens have a selectable sidebar and a segmented picker, which watchOS doesn't have.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct SidecarWatchLayoutTests {
        @Test("On watchOS a sidecar shows only the plugins it names: Console and Network don't build there")
        func noDefaultPlugins() {
            let actual = DebugDrawerSidecarPlugin.defaults

            #expect(actual.isEmpty)
        }

        @Test("On watchOS each app listed is a row that pushes its screen")
        func appsArePushedRows() throws {
            let store = FileManager.default.temporaryDirectory.appending(path: "SidecarWatchLayoutTests-\(UUID().uuidString)")
            let apps = [
                DebugDrawerSidecarApp(
                    bundleIdentifier: "com.example.shop", displayName: "Shop", version: "2.4", build: "881",
                    capabilities: ["DebugDrawer.Sessions"], protocolVersion: 2, lastSeen: Date(), storeDirectory: store
                ),
                DebugDrawerSidecarApp(
                    bundleIdentifier: "com.example.wallet", displayName: "Wallet", version: "1.0", build: "12",
                    capabilities: ["DebugDrawer.Sessions"], protocolVersion: 2, lastSeen: Date(), storeDirectory: store
                )
            ]
            let sut = SidecarAppListView(apps: apps, error: nil, selection: .constant(nil))

            let rows = try sut.inspect().findAll(ViewType.NavigationLink.self)
            let actual = try rows.map { try $0.labelView().find(SidecarAppRow.self).actualView().app.displayName }

            #expect(actual == ["Shop", "Wallet"])
        }

        @Test("On watchOS an app's screen lists each plugin it serves as a row that pushes it, with no picker")
        func pluginsArePushedRows() throws {
            let app = DebugDrawerSidecarApp(
                bundleIdentifier: "com.example.shop.debug", displayName: "Shop Debug", version: "2.5", build: "900",
                capabilities: ["Shop.LogLevel", "Shop.Theme"], protocolVersion: 2, lastSeen: Date(),
                storeDirectory: FileManager.default.temporaryDirectory.appending(path: "SidecarWatchLayoutTests-\(UUID().uuidString)")
            )
            let plugins = ["Shop.LogLevel", "Shop.Theme"].map { id in
                DebugDrawerSidecarPlugin(
                    id: id, title: id, icon: "slider.horizontal.3", snapshot: LevelSnapshot.self, command: LevelCommand.self
                ) { LevelPlugin(transport: $0) }
            }
            let connection = try DebugDrawerSidecarConnection(app: app)
            let sut = SidecarConnectedScreen(connection: connection, plugins: plugins, layout: .platform, sessionDuration: 60, grant: nil)

            let view = try sut.inspect()
            let rows = view.findAll(ViewType.NavigationLink.self)
            let titles = try rows.map { try $0.labelView().find(ViewType.Label.self).title().text().string() }

            #expect(SidecarPluginLayout.platform == .rows)
            #expect(titles == ["Shop.LogLevel", "Shop.Theme"])
            #expect(throws: (any Error).self) { try view.find(ViewType.Picker.self) }
            #expect(try view.find(button: "Create Report").isDisabled())
            connection.close()
        }
    }
#endif
