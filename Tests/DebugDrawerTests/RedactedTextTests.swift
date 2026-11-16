// Views render on the Mac; ViewInspector is linked on Apple platforms only.
#if os(macOS)
    @testable import DebugDrawer
    import SwiftUI
    import Testing
    import ViewInspector

    @MainActor
    @Suite(.serialized, .timeLimit(.minutes(1)))
    struct RedactedTextTests {
        @Test("A masked value shows the mask and a Reveal button")
        func masked() throws {
            let sut = RedactedText("Bearer abc", redacted: DebugDrawerRedaction.mask)
            let expected = DebugDrawerRedaction.mask

            let actual = try sut.inspect().find(ViewType.Text.self).string()
            let label = try sut.inspect().find(ViewType.Button.self).accessibilityLabel().string()

            #expect(actual == expected)
            #expect(label == "Reveal value")
        }

        @Test("Pressing Reveal shows the value, and pressing Hide masks it again")
        func reveal() async throws {
            let sut = RedactedText("Bearer abc", redacted: DebugDrawerRedaction.mask)
            let expectedRevealed = "Bearer abc"
            let expectedHidden = DebugDrawerRedaction.mask

            try await ViewHosting.host(sut) {
                try await sut.inspection.inspect { view in
                    try view.find(ViewType.Button.self).tap()
                }
                try await sut.inspection.inspect { view in
                    let actual = try view.find(ViewType.Text.self).string()
                    let label = try view.find(ViewType.Button.self).accessibilityLabel().string()
                    #expect(actual == expectedRevealed)
                    #expect(label == "Hide value")
                    try view.find(ViewType.Button.self).tap()
                }
                try await sut.inspection.inspect { view in
                    let actual = try view.find(ViewType.Text.self).string()
                    #expect(actual == expectedHidden)
                }
            }
        }

        @Test("A value with nothing redacted shows as plain text with no button")
        func plain() throws {
            let sut = RedactedText("application/json", redacted: "application/json")

            let actual = try sut.inspect().find(ViewType.Text.self).string()
            let buttons = try sut.inspect().findAll(ViewType.Button.self)

            #expect(actual == "application/json")
            #expect(buttons.isEmpty)
        }
    }
#endif
