// iOS, and Mac Catalyst, whose scenes are UIKit's too: a Catalyst scene's windows share its Mac
// window, so a window of the scene's own at a higher level draws over the app's there as on iOS.
#if DEBUG && os(iOS)
    import SwiftUI
    import UIKit

    // A window of the drawer's own, above the app's windows, rather than an overlay in the app's
    // root view: a sheet, a full-screen cover or an alert is presented above that root view, so
    // an overlay in it is covered by what it needs to inspect. Beside a regular panel the window
    // lets every touch fall through to the app's windows below it, except while a context menu or
    // sheet from the panel shows (UIKit draws it in this window and closes it on a tap this window
    // gets); around a compact one, which leaves the app no room to use, a tap closes the drawer.

    /// The drawer's window in one scene: at a level above alerts, hosting the panel, and hidden
    /// while the drawer is closed.
    final class DrawerSceneWindow: UIWindow, DrawerPresentationHost {
        /// Above `.alert`, so a presented alert's window stays under the panel.
        static let level = UIWindow.Level(rawValue: UIWindow.Level.alert.rawValue + 1)

        let presentation: DrawerPresentation

        /// A window for `presentation`'s drawer in `scene`, which sizes it; with no scene, a window
        /// of zero size until it is given a frame.
        init(scene: UIWindowScene?, drawer: DebugDrawer, presentation: DrawerPresentation) {
            self.presentation = presentation
            if let scene {
                super.init(windowScene: scene)
            } else {
                super.init(frame: .zero)
            }
            windowLevel = Self.level
            backgroundColor = .clear
            isHidden = true
            let root = UIHostingController(rootView: DebugDrawerOverlay(drawer: drawer, presentation: presentation)
                .accessibilityIdentifier(debugDrawerOverlayIdentifier))
            root.view.backgroundColor = .clear
            rootViewController = root
            presentation.host = self
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            // Can't fire: unavailable, so no code can call it, and the type isn't public, so no
            // storyboard or nib names it; the system decodes only views an archive names.
            fatalError("The drawer's window is made in code.")
        }

        /// Takes a touch on the open panel, anywhere on the backdrop behind a compact one, which
        /// closes the drawer, and every touch while a context menu, sheet or popover from the panel
        /// shows, so a tap beside it closes it and its items past the panel's edge can be chosen;
        /// everywhere else `nil`, so UIKit offers it to the app's windows below.
        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            guard Self.takesTouch(
                at: point,
                panelFrame: presentation.panelFrame,
                layout: presentation.layout,
                isOpen: presentation.isOpen
            ) || hasSubviews(besides: rootViewController?.view) else { return nil }
            return super.hitTest(point, with: event)
        }

        /// Whether the drawer's window takes a touch at `point`: only while the drawer is open and
        /// its panel drawn; then on a regular panel only, so the app beside it stays usable, and
        /// anywhere around a compact one, whose backdrop closes the drawer like a sheet's.
        ///
        /// - Parameters:
        ///   - point: The touch, in the window's coordinates.
        ///   - panelFrame: Where the panel is drawn, or `nil` while it isn't.
        ///   - layout: The panel's width class.
        ///   - isOpen: Whether the drawer is open.
        /// - Returns: `true` when the touch belongs to the drawer.
        static func takesTouch(at point: CGPoint, panelFrame: CGRect?, layout: DrawerPanelLayout, isOpen: Bool) -> Bool {
            guard isOpen, let panelFrame else { return false }
            switch layout {
            case .regular: return panelFrame.contains(point)
            case .compact: return true
            }
        }

        func drawerWillShow() {
            isHidden = false
        }

        /// Hides the window, first handing keyboard focus back to the app's frontmost window if the
        /// drawer's search field had it, so the app's keyboard shortcuts and text fields work again.
        func drawerDidHide() {
            guard !presentation.isOpen else { return }
            if isKeyWindow {
                windowScene?.windows
                    .filter { !isDebugDrawerWindow($0) && !$0.isHidden }
                    .max { $0.windowLevel < $1.windowLevel }?
                    .makeKey()
            }
            isHidden = true
        }
    }
#endif
