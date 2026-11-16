// Views render on the Mac; ViewInspector is linked on Apple platforms only.
#if os(macOS)
    @testable import DebugDrawer
    import SwiftUI
    import Testing
    import ViewInspector

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct StatBadgeTests {
        @Test("A badge shows its figure over its caption")
        func figureOverCaption() throws {
            let sut = DebugDrawerStatBadge("Avg Time", value: "120ms")
            let expected = ["120ms", "Avg Time"]

            let actual = try sut.inspect().findAll(ViewType.Text.self).map { try $0.string() }

            #expect(actual == expected)
        }

        @Test("VoiceOver reads the caption as the label and the figure as the value")
        func accessibility() throws {
            let sut = DebugDrawerStatBadge("Min", value: "41", color: .red)
            let expectedLabel = "Min"
            let expectedValue = "41"

            let stack = try sut.inspect().find(ViewType.VStack.self)
            let actualLabel = try stack.accessibilityLabel().string()
            let actualValue = try stack.accessibilityValue().string()

            #expect(actualLabel == expectedLabel)
            #expect(actualValue == expectedValue)
        }

        @Test("The figure takes the badge's color")
        func color() throws {
            let sut = DebugDrawerStatBadge("Peak", value: "182", color: .blue)
            let expected = Color.blue

            let actual = try sut.inspect().find(text: "182").attributes().foregroundColor()

            #expect(actual == expected)
        }
    }
#endif
