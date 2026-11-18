// Views render on the Mac; ViewInspector is linked on Apple platforms only.
#if os(macOS)
    @testable import DebugDrawer
    import SwiftUI
    import Testing
    import ViewInspector

    private struct ChromePlugin: DebugDrawerPlugin {
        var title = "Loaded Libraries"
        var icon = "books.vertical"
        var body: some View { EmptyView() }
    }

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct DrawerChromeAccessibilityTests {
        @Test("The header's title is a heading")
        func headerTitleIsAHeading() throws {
            let sut = DrawerHeader(isReportInProgress: false, createReport: {}, close: {})

            let actual = try sut.inspect().find(text: "Debug").accessibilityTraits()

            #expect(actual.contains(.isHeader))
        }

        @Test("The header's close button is labelled and closes the drawer")
        func closeButton() throws {
            var closed = 0
            let sut = DrawerHeader(isReportInProgress: false, createReport: {}, close: { closed += 1 })

            try sut.inspect().find(ViewType.Button.self) { try $0.accessibilityLabel().string() == "Close the debug drawer" }.tap()

            #expect(closed == 1)
        }

        @Test("The header's report button is labelled and creates a report")
        func reportButton() throws {
            var created = 0
            let sut = DrawerHeader(isReportInProgress: false, createReport: { created += 1 }, close: {})

            try sut.inspect().find(ViewType.Button.self) { try $0.accessibilityLabel().string() == "Create a bug report" }.tap()

            #expect(created == 1)
        }

        @Test("Every button in the header has a label")
        func everyHeaderButtonIsLabelled() throws {
            let sut = DrawerHeader(isReportInProgress: false, createReport: {}, close: {})
            let expected = ["Create a bug report", "Close the debug drawer"]

            let actual = try sut.inspect().findAll(ViewType.Button.self).map { try $0.accessibilityLabel().string() }

            #expect(actual == expected)
        }

        @Test("Each navigator tab is named for its category, and only the selected one reads as selected")
        func navigatorTabs() throws {
            let tabs = [
                DrawerNavigatorTab(scope: .all, title: "All", systemImage: "square.grid.2x2", hasUnread: true),
                DrawerNavigatorTab(scope: .category("Storage"), title: "Storage", systemImage: "externaldrive", hasUnread: true)
            ]
            let sut = DrawerNavigatorTabs(tabs: tabs, selection: .constant(.category("Storage")))
            let expectedLabels = ["All", "Storage"]
            let expectedSelected = [false, true]
            let expectedValues = ["Unread", "Unread"]

            let buttons = try sut.inspect().findAll(ViewType.Button.self)
            let labels = try buttons.map { try $0.accessibilityLabel().string() }
            let selected = try buttons.map { try $0.accessibilityTraits().contains(.isSelected) }
            let values = try buttons.map { try $0.accessibilityValue().string() }

            #expect(labels == expectedLabels)
            #expect(selected == expectedSelected)
            #expect(values == expectedValues)
        }

        @Test("Tapping a navigator tab selects its scope")
        func tappingATabSelectsIt() throws {
            var scope = DrawerScope.all
            let binding = Binding(get: { scope }, set: { scope = $0 })
            let tabs = [
                DrawerNavigatorTab(scope: .all, title: "All", systemImage: "square.grid.2x2", hasUnread: false),
                DrawerNavigatorTab(scope: .category("App"), title: "App", systemImage: "app.badge", hasUnread: false)
            ]
            let sut = DrawerNavigatorTabs(tabs: tabs, selection: binding)
            let expected = DrawerScope.category("App")

            try sut.inspect().findAll(ViewType.Button.self)[1].tap()

            #expect(scope == expected)
        }

        @Test("The scope toggles say whether they're on")
        func scopeToggles() throws {
            var isOn = false
            let binding = Binding(get: { isOn }, set: { isOn = $0 })
            let sut = DrawerScopeToggle(title: "Show only my code", systemImage: "person.crop.square", isOn: binding)

            let label = try sut.inspect().button().accessibilityLabel().string()
            try sut.inspect().button().tap()

            #expect(label == "Show only my code")
            #expect(isOn)
        }

        @Test("A plugin's section header is a heading named for the plugin")
        func pluginHeaderIsANamedHeading() throws {
            let sut = PluginSectionHeader(
                plugin: AnyDebugDrawerPlugin(ChromePlugin()),
                isExpanded: true,
                isPinned: false,
                badge: nil,
                isMovable: false,
                toggle: {}
            )

            let button = try sut.inspect().find(ViewType.Button.self)
            let label = try button.accessibilityLabel().string()
            let traits = try button.accessibilityTraits()

            #expect(label == "Loaded Libraries")
            #expect(traits.contains(.isHeader))
        }

        @Test("An expanded section's header says it is expanded")
        func expandedValue() throws {
            let sut = PluginSectionHeader(
                plugin: AnyDebugDrawerPlugin(ChromePlugin()),
                isExpanded: true,
                isPinned: false,
                badge: nil,
                isMovable: false,
                toggle: {}
            )
            let expected = "Expanded"

            let actual = try sut.inspect().find(ViewType.Button.self).accessibilityValue().string()

            #expect(actual == expected)
        }

        @Test("A collapsed section's header says it is collapsed")
        func collapsedValue() throws {
            let sut = PluginSectionHeader(
                plugin: AnyDebugDrawerPlugin(ChromePlugin()),
                isExpanded: false,
                isPinned: false,
                badge: nil,
                isMovable: false,
                toggle: {}
            )
            let expected = "Collapsed"

            let actual = try sut.inspect().find(ViewType.Button.self).accessibilityValue().string()

            #expect(actual == expected)
        }

        @Test("A pinned, badged section's header reads its pin and count after its state")
        func pinnedAndBadgedValue() throws {
            let sut = PluginSectionHeader(
                plugin: AnyDebugDrawerPlugin(ChromePlugin()),
                isExpanded: false,
                isPinned: true,
                badge: 3,
                isMovable: true,
                toggle: {}
            )
            let expected = "Collapsed, Pinned, 3 new"

            let actual = try sut.inspect().find(ViewType.Button.self).accessibilityValue().string()

            #expect(actual == expected)
        }

        @Test("A global plugin's header hints that its actions pin, move and silence it; a local one's that they silence it")
        func hints() throws {
            let plugin = AnyDebugDrawerPlugin(ChromePlugin())
            let global = PluginSectionHeader(plugin: plugin, isExpanded: true, isPinned: false, badge: nil, isMovable: true, toggle: {})
            let local = PluginSectionHeader(plugin: plugin, isExpanded: true, isPinned: false, badge: nil, isMovable: false, toggle: {})

            let globalHint = try global.inspect().find(ViewType.Button.self).accessibilityHint().string()
            let localHint = try local.inspect().find(ViewType.Button.self).accessibilityHint().string()

            #expect(globalHint == "Toggles the section. Its actions pin it, move it or silence its notices.")
            #expect(localHint == "Toggles the section. Its actions silence its notices.")
        }

        @Test("Pressing a plugin's section header toggles the section")
        func pressingToggles() throws {
            var toggled = 0
            let sut = PluginSectionHeader(
                plugin: AnyDebugDrawerPlugin(ChromePlugin()),
                isExpanded: true,
                isPinned: false,
                badge: nil,
                isMovable: false,
                toggle: { toggled += 1 }
            )

            try sut.inspect().find(ViewType.Button.self).tap()

            #expect(toggled == 1)
        }
    }
#endif
