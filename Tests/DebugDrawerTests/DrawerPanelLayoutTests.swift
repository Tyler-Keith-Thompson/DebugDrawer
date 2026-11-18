#if DEBUG
    @testable import DebugDrawer
    import SwiftUI
    import Testing

    @MainActor
    @Suite("Drawer panel layout")
    struct DrawerPanelLayoutTests {
        @Test("A window narrower than two regular panels gets a compact panel: every iPhone in portrait, Slide Over, a narrow Mac window",
              arguments: [CGFloat(320), 375, 393, 430, 631])
        func compactWidths(width: CGFloat) {
            let actual = DrawerPanelLayout(windowWidth: width)

            #expect(actual == .compact)
        }

        @Test("A window at least two regular panels wide keeps the 316 point panel: an iPhone in landscape, an iPad, a Mac window",
              arguments: [CGFloat(632), 667, 744, 1024, 1440])
        func regularWidths(width: CGFloat) {
            let actual = DrawerPanelLayout(windowWidth: width)

            #expect(actual == .regular)
        }

        @Test("A regular panel is 316 points wide")
        func regularWidth() {
            let expected: CGFloat = 316

            let actual = DrawerPanelLayout.regularWidth

            #expect(actual == expected)
        }

        @Test("A compact panel keeps an 8 point margin inside the safe area on every side")
        func compactInsets() {
            let expected = EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)

            let actual = EdgeInsets.drawerPanel(layout: .compact)

            #expect(actual == expected)
        }

        @Test("A regular panel keeps an 8 point margin inside the safe area and leaves its leading edge open to the app")
        func regularInsets() {
            let expected = EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 8)

            let actual = EdgeInsets.drawerPanel(layout: .regular)

            #expect(actual == expected)
        }

        @Test("The drawer's modifier applies no animation to the app's content: none of its layers is an animation modifier")
        func modifierAnimatesNoHostContent() {
            let body = String(reflecting: DebugDrawerModifier.Body.self)

            let actual = body.contains("Animation")

            #expect(!body.isEmpty)
            #expect(!actual, "\(body)")
        }
    }
#endif
