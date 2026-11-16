#if DEBUG
    @testable import DebugDrawer
    import SwiftUI
    import Testing
    import ViewInspector

    @MainActor
    @Suite("Drawer panel placement")
    struct DrawerPanelPlacementTests {
        @Test("The panel's top inset is the safe area's, so it sits below the status bar")
        func topInsetIsTheSafeAreas() {
            let safeArea = EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)
            let expected: CGFloat = 59

            let actual = EdgeInsets.drawerPanel(safeArea: safeArea).top

            #expect(actual == expected)
        }

        @Test("The panel's bottom and trailing insets are the safe area's where it has them")
        func bottomAndTrailingInsetsAreTheSafeAreas() {
            let safeArea = EdgeInsets(top: 0, leading: 59, bottom: 21, trailing: 59)
            let expected = EdgeInsets(top: 8, leading: 0, bottom: 21, trailing: 59)

            let actual = EdgeInsets.drawerPanel(safeArea: safeArea)

            #expect(actual == expected)
        }

        @Test("With no safe area the panel keeps an 8 pt margin from the window's edges")
        func noSafeAreaKeepsTheMargin() {
            let expected = EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 8)

            let actual = EdgeInsets.drawerPanel(safeArea: EdgeInsets())

            #expect(actual == expected)
        }

        @Test("The close button's target is at least 44 points on a touch screen, and its 22 point square on the Mac, as Xcode's pane buttons are")
        func closeButtonTarget() throws {
            let sut = DrawerCloseButton {}
            #if os(macOS)
                let expected: CGFloat = 22
            #else
                let expected: CGFloat = 44
            #endif

            let actual = try sut.inspect().find(ViewType.Image.self).flexFrame()

            #expect(actual.minWidth == expected)
            #expect(actual.minHeight == expected)
        }

        @Test("Tapping the close button runs its action")
        func tappingTheCloseButtonRunsItsAction() throws {
            var tapped = false
            let sut = DrawerCloseButton { tapped = true }

            try sut.inspect().button().tap()

            #expect(tapped)
        }
    }
#endif
