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
            let sut = DrawerHeader(isCreatingReport: false, createReport: {}, close: {})

            let actual = try sut.inspect().find(text: "Debug").accessibilityTraits()

            #expect(actual.contains(.isHeader))
        }

        @Test("The header's close button is labelled and closes the drawer")
        func closeButton() throws {
            var closed = 0
            let sut = DrawerHeader(isCreatingReport: false, createReport: {}, close: { closed += 1 })

            try sut.inspect().find(ViewType.Button.self) { try $0.accessibilityLabel().string() == "Close the debug drawer" }.tap()

            #expect(closed == 1)
        }

        @Test("The header's report button is labelled and creates a report")
        func reportButton() throws {
            var created = 0
            let sut = DrawerHeader(isCreatingReport: false, createReport: { created += 1 }, close: {})

            try sut.inspect().find(ViewType.Button.self) { try $0.accessibilityLabel().string() == "Create a bug report" }.tap()

            #expect(created == 1)
        }

        @Test("Every button in the header has a label")
        func everyHeaderButtonIsLabelled() throws {
            let sut = DrawerHeader(isCreatingReport: false, createReport: {}, close: {})
            let expected = ["Create a bug report", "Close the debug drawer"]

            let actual = try sut.inspect().findAll(ViewType.Button.self).map { try $0.accessibilityLabel().string() }

            #expect(actual == expected)
        }

        @Test("A group's title is a heading")
        func groupTitleIsAHeading() throws {
            let sut = DrawerSectionHeader(title: "Pinned")

            let actual = try sut.inspect().find(text: "Pinned").accessibilityTraits()

            #expect(actual.contains(.isHeader))
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

        @Test("A global plugin's header hints that its actions pin and move it; a local one's doesn't")
        func hints() throws {
            let plugin = AnyDebugDrawerPlugin(ChromePlugin())
            let global = PluginSectionHeader(plugin: plugin, isExpanded: true, isPinned: false, badge: nil, isMovable: true, toggle: {})
            let local = PluginSectionHeader(plugin: plugin, isExpanded: true, isPinned: false, badge: nil, isMovable: false, toggle: {})

            let globalHint = try global.inspect().find(ViewType.Button.self).accessibilityHint().string()
            let localHint = try local.inspect().find(ViewType.Button.self).accessibilityHint().string()

            #expect(globalHint == "Toggles the section. Its actions pin it or move it.")
            #expect(localHint == "Toggles the section.")
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
