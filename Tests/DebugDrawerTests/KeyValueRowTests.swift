// Views render on the Mac; ViewInspector is linked on Apple platforms only.
#if os(macOS)
    @testable import DebugDrawer
    import SwiftUI
    import Testing
    import ViewInspector

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct KeyValueRowTests {
        @Test("A row shows its label and its value")
        func plain() throws {
            let sut = DebugDrawerKeyValueRow("Version", value: "1.4.2 (88)")
            let expectedLabel = "Version"
            let expectedValue = "1.4.2 (88)"

            let actual = try sut.inspect().findAll(ViewType.Text.self).map { try $0.string() }

            #expect(actual == [expectedLabel, expectedValue])
        }

        @Test("A row with nothing redacted has no Reveal button")
        func plainHasNoButton() throws {
            let sut = DebugDrawerKeyValueRow("Path", value: "/")

            let actual = try sut.inspect().findAll(ViewType.Button.self)

            #expect(actual.isEmpty)
        }

        @Test("A redacted row shows the redacted form and a Reveal button, not the value")
        func redacted() throws {
            let sut = DebugDrawerKeyValueRow("Value", value: "t0k3n", redacted: DebugDrawerRedaction.mask)
            let expected = ["Value", DebugDrawerRedaction.mask]
            let expectedButtonLabel = "Reveal value"

            let actual = try sut.inspect().findAll(ViewType.Text.self).map { try $0.string() }
            let buttonLabel = try sut.inspect().find(ViewType.Button.self).accessibilityLabel().string()

            #expect(actual == expected)
            #expect(buttonLabel == expectedButtonLabel)
        }

        @Test("A redacted form equal to the value shows it plainly")
        func redactedEqualToValue() throws {
            let sut = DebugDrawerKeyValueRow("Domain", value: "example.com", redacted: "example.com")

            let actual = try sut.inspect().findAll(ViewType.Button.self)

            #expect(actual.isEmpty)
        }

        @Test("An empty value still shows its label")
        func emptyValue() throws {
            let sut = DebugDrawerKeyValueRow("Label", value: "")
            let expected = ["Label", ""]

            let actual = try sut.inspect().findAll(ViewType.Text.self).map { try $0.string() }

            #expect(actual == expected)
        }
    }
#endif
