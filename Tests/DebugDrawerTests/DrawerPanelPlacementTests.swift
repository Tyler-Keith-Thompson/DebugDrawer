// ViewInspector isn't linked on visionOS (APPLE_ONLY_PACKAGE_EXCLUDED_PLATFORMS in
// scripts/modules.py), and every test here inspects the close button.
#if DEBUG && !os(visionOS)
    @testable import DebugDrawer
    import SwiftUI
    import Testing
    import ViewInspector

    @MainActor
    @Suite("Drawer panel placement")
    struct DrawerPanelPlacementTests {
        // watchOS draws no panel header, so no close button (DrawerHeader): its drawer is a
        // navigation list (DrawerWatchList), and its smaller default text scales the metric below 44.
        #if !os(watchOS)
            @Test("The close button's target is at least 44 points on a touch screen, and its 22 point square on the Mac, as Xcode's panes' are")
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
        #endif

        @Test("Tapping the close button runs its action")
        func tappingTheCloseButtonRunsItsAction() throws {
            var tapped = false
            let sut = DrawerCloseButton { tapped = true }

            try sut.inspect().button().tap()

            #expect(tapped)
        }
    }
#endif
