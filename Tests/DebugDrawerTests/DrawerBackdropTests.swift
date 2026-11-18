// Views render on the Mac; ViewInspector is linked on Apple platforms only. iOS draws the backdrop
// behind a compact panel (DrawerHitTestingTests pins that its window takes the touch).
#if os(macOS)
    @testable import DebugDrawer
    import SwiftUI
    import Testing
    import ViewInspector

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct DrawerBackdropTests {
        @Test("A tap on the backdrop closes the drawer")
        func tapCloses() throws {
            var closes = 0
            let sut = DrawerBackdrop { closes += 1 }

            try sut.inspect().color().callOnTapGesture()

            #expect(closes == 1)
        }

        @Test("VoiceOver reads the backdrop as closing the drawer")
        func accessibleAsCloseButton() throws {
            let sut = DrawerBackdrop {}
            let expected = "Close the debug drawer"

            let actual = try sut.inspect().color().accessibilityLabel().string()

            #expect(actual == expected)
        }
    }
#endif
