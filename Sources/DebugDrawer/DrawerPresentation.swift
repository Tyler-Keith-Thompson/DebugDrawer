#if DEBUG
    import Combine
    import CoreGraphics

    /// One window's drawer: whether it is open, what it shows, and how wide its window lets it be.
    ///
    /// Each window (an `NSWindow` on the Mac, a `UIWindowScene` on iOS) has its own, so opening the
    /// drawer in one leaves the others as they were. ``DebugDrawer/isOpen`` and
    /// ``DebugDrawer/toggle()`` act on the key window's; platforms that draw the drawer in the
    /// app's own window (tvOS, visionOS, watchOS) have one, the drawer's detached presentation.
    @MainActor
    final class DrawerPresentation: ObservableObject {
        /// Whether the drawer is on screen in this window.
        @Published var isOpen = false {
            // The window is ordered in before the change is published, so the panel's view,
            // in that window, updates and slides in: a view in a hidden window misses the update.
            willSet {
                if newValue, !isOpen { host?.drawerWillShow() }
            }
            didSet {
                guard isOpen != oldValue else { return }
                DebugDrawer.shared.presentationDidChange()
            }
        }

        /// A plugin the drawer should show the next time it can: expanded and scrolled to in the
        /// outline, or alone.
        @Published var revealRequest: String?

        /// The outline of every plugin, or one plugin alone.
        @Published var navigation = DrawerNavigation.outline

        /// The panel's width class, from the width of the window it opens in.
        @Published var layout = DrawerPanelLayout.regular

        /// Where the open panel is, in its window's coordinates, for the window's hit testing;
        /// `nil` while nothing is drawn.
        var panelFrame: CGRect?

        /// The window the drawer is drawn in, told when to show and that the panel has gone.
        weak var host: (any DrawerPresentationHost)?

        init() {}
    }

    /// A window of the drawer's own, which shows itself when the drawer opens and hides once the
    /// panel's closing animation has finished, so the panel's transition is what the user sees.
    @MainActor
    protocol DrawerPresentationHost: AnyObject {
        /// The drawer is about to open: order the window in.
        func drawerWillShow()
        /// The panel has finished closing: order the window out.
        func drawerDidHide()
    }
#endif
