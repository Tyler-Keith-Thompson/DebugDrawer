// Views render on the Mac; ViewInspector is linked on Apple platforms only.
#if os(macOS)
    @testable import DebugDrawer
    import SwiftUI
    import Testing
    import ViewInspector

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct HeaderAccessoryTests {
        @Test("A plugin that declares no header accessory has none")
        func noAccessory() {
            let sut = AnyDebugDrawerPlugin(PlainHeaderPlugin())

            let actual = sut.headerAccessory

            #expect(actual == nil)
        }

        @Test("A plugin's header accessory is drawn beside its header, whether the plugin is open or closed",
              arguments: [true, false])
        func accessoryBesideHeader(isExpanded: Bool) throws {
            let plugin = AnyDebugDrawerPlugin(SummaryHeaderPlugin())
            let sut = DrawerPluginSection(plugin: plugin, isExpanded: isExpanded) { Text("Header") }
            let expected = "1,204 lines"

            let actual = try sut.inspect().find(text: expected).string()

            #expect(actual == expected)
        }

        @Test("A plugin with a header accessory shows no badge count in its header; one without shows it")
        func accessoryReplacesBadge() throws {
            let withAccessory = PluginHeaderLabel(plugin: AnyDebugDrawerPlugin(SummaryHeaderPlugin()), isExpanded: false, isPinned: false, badge: 3)
            let withoutAccessory = PluginHeaderLabel(plugin: AnyDebugDrawerPlugin(PlainHeaderPlugin()), isExpanded: false, isPinned: false, badge: 3)
            let badgeLabel = "3 new"

            let hidden = try withAccessory.inspect().findAll(ViewType.Text.self) { try $0.accessibilityLabel().string() == badgeLabel }
            let shown = try withoutAccessory.inspect().findAll(ViewType.Text.self) { try $0.accessibilityLabel().string() == badgeLabel }

            #expect(hidden.isEmpty)
            #expect(shown.count == 1)
        }

        @Test("An action in the header accessory runs apart from the header's own toggle")
        func accessoryAction() throws {
            var copied = 0
            var toggled = 0
            let plugin = AnyDebugDrawerPlugin(ActionHeaderPlugin { copied += 1 })
            let sut = DrawerPluginSection(plugin: plugin, isExpanded: false) {
                Button("Header") { toggled += 1 }
            }

            try sut.inspect().find(button: "Copy").tap()

            #expect(copied == 1)
            #expect(toggled == 0)
        }

        @Test("An issue count shows its glyph and figures and reads as the count and what it counts")
        func issueCount() throws {
            let sut = DebugDrawerIssueCount(.warning, count: 4)
            let expectedText = "4"
            let expectedLabel = "4 warnings"

            let actualText = try sut.inspect().find(ViewType.Text.self) { try $0.string() == expectedText }.string()
            let actualLabel = try sut.inspect().find(DrawerIssueCountFace.self).hStack().accessibilityLabel().string()

            #expect(actualText == expectedText)
            #expect(actualLabel == expectedLabel)
        }

        @Test("An issue count names one in the singular and many in the plural, in every severity")
        func spokenLabels() {
            let counts = [
                DebugDrawerIssueCount(.error, count: 1),
                DebugDrawerIssueCount(.error, count: 2),
                DebugDrawerIssueCount(.warning, count: 1),
                DebugDrawerIssueCount(.ok, count: 3),
                DebugDrawerIssueCount(.neutral, count: 0)
            ]
            let expected = ["1 error", "2 errors", "1 warning", "3 OK", "0 unknown"]

            let actual = counts.map(\.spokenLabel)

            #expect(actual == expected)
        }
    }

    private struct PlainHeaderPlugin: DebugDrawerPlugin {
        let title = "Plain"
        let icon = "circle"
        var body: some View { EmptyView() }
    }

    private struct SummaryHeaderPlugin: DebugDrawerPlugin {
        let title = "Console"
        let icon = "terminal"
        var body: some View { Text("Body") }
        var headerAccessory: some View { Text("1,204 lines") }
    }

    private struct ActionHeaderPlugin: DebugDrawerPlugin {
        let title = "App Info"
        let icon = "info.circle"
        let copy: () -> Void
        var body: some View { EmptyView() }
        var headerAccessory: some View { Button("Copy", action: copy) }
    }
#endif
