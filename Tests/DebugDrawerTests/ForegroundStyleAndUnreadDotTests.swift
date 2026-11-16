// Views render on the Mac; ViewInspector is linked on Apple platforms only.
#if os(macOS)
    @testable import DebugDrawer
    import SwiftUI
    import Testing
    import ViewInspector

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct ForegroundStyleAndUnreadDotTests {
        @Test("Each foreground style takes its palette color, error text apart from the glyphs' red")
        func foregroundColors() {
            let expected: [DebugDrawerForegroundStyle: Color] = [
                .primary: DrawerPalette.text,
                .secondary: DrawerPalette.secondaryText,
                .tertiary: DrawerPalette.tertiaryText,
                .accent: DrawerPalette.accent,
                .error: DrawerPalette.errorText
            ]

            let actual = Dictionary(uniqueKeysWithValues: DebugDrawerForegroundStyle.allCases.map { ($0, $0.color) })

            #expect(actual == expected)
        }

        @Test("A gauge's or graph's fill is the accent with no severity, and the issue's color with one")
        func fills() {
            let severities: [DebugDrawerIssueGlyph.Severity?] = [nil, .error, .warning, .ok, .neutral]
            let expected = [DrawerPalette.accent, DrawerPalette.error, DrawerPalette.warning, DrawerPalette.ok, DrawerPalette.systemGray]

            let actual = severities.map(DrawerPalette.fill(for:))

            #expect(actual == expected)
        }

        @Test("The unread dot reads as Unread")
        func unreadDot() throws {
            let sut = DebugDrawerUnreadDot()
            let expected = "Unread"

            let actual = try sut.inspect().find(DrawerUnreadDotFace.self).shape().accessibilityLabel().string()

            #expect(actual == expected)
        }
    }
#endif
