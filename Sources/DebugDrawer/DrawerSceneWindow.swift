// iOS, and Mac Catalyst, whose scenes are UIKit's too: a Catalyst scene's windows share its Mac
// window, so a window of the scene's own at a higher level draws over the app's there as on iOS.
#if DEBUG && os(iOS)
    import SwiftUI
    import UIKit

    // A window of the drawer's own, above the app's windows, rather than an overlay in the app's
    // root view: a sheet, a full-screen cover or an alert is presented above that root view, so
    // an overlay in it is covered by what it needs to inspect. The window lets every touch outside
    // the panel fall through to the app's windows below it.

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
            fatalError("The drawer's window is made in code.")
        }

        /// Takes a touch only on the open panel; everywhere else `nil`, so UIKit offers it to the
        /// app's windows below.
        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            guard Self.takesTouch(at: point, panelFrame: presentation.panelFrame, isOpen: presentation.isOpen) else { return nil }
            return super.hitTest(point, with: event)
        }

        /// Whether the drawer's window takes a touch at `point`: only while the drawer is open, and
        /// only on its panel.
        ///
        /// - Parameters:
        ///   - point: The touch, in the window's coordinates.
        ///   - panelFrame: Where the panel is drawn, or `nil` while it isn't.
        ///   - isOpen: Whether the drawer is open.
        /// - Returns: `true` when the touch belongs to the drawer.
        static func takesTouch(at point: CGPoint, panelFrame: CGRect?, isOpen: Bool) -> Bool {
            guard isOpen, let panelFrame else { return false }
            return panelFrame.contains(point)
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
                    .filter { !($0 is DrawerSceneWindow) && !$0.isHidden }
                    .max { $0.windowLevel < $1.windowLevel }?
                    .makeKey()
            }
            isHidden = true
        }
    }
#endif
