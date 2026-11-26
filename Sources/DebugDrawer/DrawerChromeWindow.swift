// iOS, and Mac Catalyst, whose scenes are UIKit's too (DrawerSceneWindow).
#if DEBUG && os(iOS)
    import SwiftUI
    import UIKit

    // The HUD and the toast in a window of the drawer's own, as the panel is (DrawerSceneWindow),
    // rather than in the app's root view: `attach(to:)` then shows them in a UIKit app with no
    // SwiftUI view, they stay above the app's sheets and alerts, and a scene that has both
    // `debugDrawer()` and `attach(to:)` draws them once. A window of its own rather than the
    // panel's: the panel's window has a root view controller, which decides the status bar and the
    // orientations while it shows, so it shows only while the drawer is open, and the HUD shows
    // while it is closed. This one hosts its view as a plain subview, as DrawerOverlayWindow does,
    // so the app's windows keep deciding those, and it stays on screen, so SwiftUI keeps it up to
    // date. It takes a touch only on the HUD's card and the toast, or anywhere while a readout's
    // context menu shows (UIKit draws the menu in this window, past the card, and closes it on a
    // tap this window gets); every other touch falls through to the app's windows below.

    /// The drawer's HUD and toast in one scene: a window at a level above alerts and under the
    /// drawer's panel, taking touches only where the HUD's card or the toast is drawn, or anywhere
    /// while a readout's context menu shows.
    final class DrawerChromeWindow: UIWindow {
        /// Above the plugins' overlay (DrawerOverlayWindow) and alerts, under the drawer's panel.
        static let level = UIWindow.Level(rawValue: UIWindow.Level.alert.rawValue + 0.75)

        /// Where the HUD's card and the toast are drawn, in the window's coordinates.
        let frames: DrawerChromeFrames
        private let hosting: UIViewController

        /// A window covering `scene` drawing `drawer`'s HUD and toast; with no scene, a window of
        /// zero size until it is given a frame.
        init(scene: UIWindowScene?, drawer: DebugDrawer) {
            let frames = DrawerChromeFrames()
            let hosting = UIHostingController(rootView: DrawerChromeContent(drawer: drawer, frames: frames))
            hosting.view.backgroundColor = .clear
            self.frames = frames
            self.hosting = hosting
            if let scene {
                super.init(windowScene: scene)
            } else {
                super.init(frame: .zero)
            }
            windowLevel = Self.level
            backgroundColor = .clear
            // A plain subview, not the root view controller: the topmost window's root view
            // controller decides the status bar and the orientations, which stay the app's.
            hosting.view.frame = bounds
            hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            addSubview(hosting.view)
            isHidden = false
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            // Can't fire: unavailable, so no code can call it, and the type isn't public, so no
            // storyboard or nib names it; the system decodes only views an archive names.
            fatalError("The drawer's HUD window is made in code.")
        }

        /// Never key, so a tap on the HUD or the toast leaves the app's window key, with its
        /// keyboard shortcuts and its text fields' focus.
        override var canBecomeKey: Bool {
            false
        }

        /// Takes a touch on the HUD's card or the toast, and every touch while a readout's context
        /// menu shows, so its items can be chosen and a tap beside it closes it; otherwise `nil`,
        /// so UIKit offers the touch to the app's windows below.
        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            guard frames.contains(point) || hasSubviews(besides: hosting.view) else { return nil }
            return super.hitTest(point, with: event)
        }
    }

    /// The HUD under the toast, each reporting where it is drawn.
    private struct DrawerChromeContent: View {
        let drawer: DebugDrawer
        let frames: DrawerChromeFrames

        var body: some View {
            ZStack(alignment: .topTrailing) {
                DrawerHUDLayer(drawer: drawer) { frames.hud = $0 }
                DrawerToastLayer(drawer: drawer) { frames.toast = $0 }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
    }

    /// Where a window's HUD card and toast are drawn, for its hit testing: a class, so a move
    /// redraws nothing.
    @MainActor
    final class DrawerChromeFrames {
        /// The HUD's card, or `nil` while no readout is pinned.
        var hud: CGRect?
        /// The toast, without its margin, or `nil` while none shows.
        var toast: CGRect?

        /// Whether `point` is on the HUD's card or the toast.
        ///
        /// - Parameter point: A point in the window's coordinates.
        /// - Returns: `true` when the touch belongs to the drawer.
        func contains(_ point: CGPoint) -> Bool {
            [hud, toast].contains { $0?.contains(point) == true }
        }
    }
#endif
