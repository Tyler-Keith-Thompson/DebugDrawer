#if DEBUG && (os(macOS) || os(iOS))
    import DebugDrawer
    @testable import DebugDrawerSidecarKit
    import Foundation
    import SwiftUI
    import Testing
    import ViewInspector

    /// A model's snapshot, for the plugins the screen offers.
    private struct LevelSnapshot: Codable, Equatable, Sendable {
        var level = "info"
    }

    /// A model's commands, for the plugins the screen offers.
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

    // How an app's screen offers its plugins (DD-266): a segmented picker where the width allows,
    // and on an iPhone, where a picker of seven plugins cut their names to "Acce…", "Metri…", a
    // list with a row per plugin that pushes it, each name in full.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct SidecarPluginLayoutTests {
        @Test("In the rows layout seven plugins are seven rows, each titled in full and pushing its plugin, with no picker")
        func sevenPluginsAreRows() throws {
            // Seven of the example sidecar's capability plugins' titles, which an iPhone cut short.
            let expected = ["Accessibility", "Analytics", "Metrics", "Mocking", "Feature Flags", "Experiments", "Localization"]
            let app = DebugDrawerSidecarApp(
                bundleIdentifier: "com.example.shop.debug", displayName: "Shop Debug", version: "2.5", build: "900",
                capabilities: expected.map { "Shop.\($0)" }, protocolVersion: 2, lastSeen: Date(),
                storeDirectory: FileManager.default.temporaryDirectory.appending(path: "SidecarPluginLayoutTests-\(UUID().uuidString)")
            )
            let plugins = expected.map { title in
                DebugDrawerSidecarPlugin(
                    id: "Shop.\(title)", title: title, icon: "slider.horizontal.3", snapshot: LevelSnapshot.self, command: LevelCommand.self
                ) { LevelPlugin(transport: $0) }
            }
            let connection = try DebugDrawerSidecarConnection(app: app)
            let sut = SidecarConnectedScreen(connection: connection, plugins: plugins, layout: .rows, sessionDuration: 60, grant: nil)

            let view = try sut.inspect()
            let rows = view.findAll(ViewType.NavigationLink.self)
            let actual = try rows.map { try $0.labelView().find(ViewType.Label.self).title().text().string() }
            let pushed = try rows.map { try $0.find(SidecarPluginHost.self).actualView().plugin.title }

            #expect(actual == expected)
            #expect(pushed == expected)
            #expect(throws: (any Error).self) { try view.find(ViewType.Picker.self) }
            #expect(try view.find(button: "Create Report").isDisabled())
            connection.close()
        }

        @Test("In the picker layout seven plugins are offered as segments, each titled in full, over the first plugin, and no row pushes one")
        func sevenPluginsArePickerSegments() throws {
            // Seven of the example sidecar's capability plugins' titles, which an iPhone cut short.
            let expected = ["Accessibility", "Analytics", "Metrics", "Mocking", "Feature Flags", "Experiments", "Localization"]
            let app = DebugDrawerSidecarApp(
                bundleIdentifier: "com.example.shop.debug", displayName: "Shop Debug", version: "2.5", build: "900",
                capabilities: expected.map { "Shop.\($0)" }, protocolVersion: 2, lastSeen: Date(),
                storeDirectory: FileManager.default.temporaryDirectory.appending(path: "SidecarPluginLayoutTests-\(UUID().uuidString)")
            )
            let plugins = expected.map { title in
                DebugDrawerSidecarPlugin(
                    id: "Shop.\(title)", title: title, icon: "slider.horizontal.3", snapshot: LevelSnapshot.self, command: LevelCommand.self
                ) { LevelPlugin(transport: $0) }
            }
            let connection = try DebugDrawerSidecarConnection(app: app)
            let sut = SidecarConnectedScreen(connection: connection, plugins: plugins, layout: .picker, sessionDuration: 60, grant: nil)

            let view = try sut.inspect()
            let segments = try view.find(SidecarPluginPicker.self).findAll(ViewType.Picker.self)[0]
            let actual = try segments.findAll(ViewType.Label.self).map { try $0.title().text().string() }
            let shown = try view.find(SidecarPluginHost.self).actualView().plugin.title

            #expect(try segments.pickerStyle() is SegmentedPickerStyle)
            #expect(actual == expected)
            #expect(shown == "Accessibility")
            #expect(view.findAll(ViewType.NavigationLink.self).isEmpty)
            connection.close()
        }

        @Test("Where the segments don't fit, the picker is a menu naming every plugin in full; the segments come first, so they win where they fit")
        func pickerFallsBackToAMenu() throws {
            let expected = ["Accessibility", "Analytics", "Metrics", "Mocking", "Feature Flags", "Experiments", "Localization"]
            let plugins = expected.map { title in
                DebugDrawerSidecarPlugin(
                    id: "Shop.\(title)", title: title, icon: "slider.horizontal.3", snapshot: LevelSnapshot.self, command: LevelCommand.self
                ) { LevelPlugin(transport: $0) }
            }
            let sut = SidecarPluginPicker(plugins: plugins, selection: .constant("Shop.Metrics"))

            let pickers = try sut.inspect().find(ViewType.ViewThatFits.self).findAll(ViewType.Picker.self)
            let menu = try #require(pickers.last)
            let actual = try menu.findAll(ViewType.Label.self).map { try $0.title().text().string() }

            #expect(pickers.count == 2)
            #expect(try pickers[0].pickerStyle() is SegmentedPickerStyle)
            #expect(try menu.pickerStyle() is MenuPickerStyle)
            #expect(actual == expected)
            #expect(try menu.selectedValue(String?.self) == "Shop.Metrics")
        }

        #if os(iOS)
            @Test("On iOS a compact width (an iPhone) gets the rows; a regular one (an iPad) and none known get the picker")
            func sizeClassPicksTheLayout() {
                let compact = SidecarPluginLayout(horizontalSizeClass: .compact)
                let regular = SidecarPluginLayout(horizontalSizeClass: .regular)
                let unknown = SidecarPluginLayout(horizontalSizeClass: nil)

                #expect(compact == .rows)
                #expect(regular == .picker)
                #expect(unknown == .picker)
            }
        #else
            @Test("On the Mac an app's screen has the picker")
            func macHasThePicker() {
                let actual = SidecarPluginLayout.platform

                #expect(actual == .picker)
            }
        #endif
    }
#endif
