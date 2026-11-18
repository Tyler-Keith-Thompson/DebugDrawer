// A window of the drawer's own over the app's, for plugins that draw over the app (view borders,
// click ripples, the alignment grid) without adding a view or setting a layer property in the
// app's windows: what the app's own snapshots, screenshots and layer properties hold stays as it
// was. It takes no events, so every click and touch reaches the app's windows below it.
#if DEBUG && (os(macOS) || os(iOS))
    import SwiftUI

    #if os(macOS)
        import AppKit

        /// A borderless, transparent child window over one of the app's windows that draws
        /// `content` over the window's content view and ignores the mouse.
        ///
        /// It is ordered in with its window, moves with it, and ``followHost()`` keeps it over the
        /// content view as the window resizes. ``isDebugDrawerWindow(_:)`` is `true` for it.
        package final class DrawerOverlayWindow: NSWindow {
            /// The window it draws over.
            package private(set) weak var host: NSWindow?

            /// A window over `host`'s content view drawing `content`, which is laid out from the
            /// content view's top-leading corner, in points.
            ///
            /// - Parameters:
            ///   - host: The app's window.
            ///   - content: What to draw over it.
            package init(over host: NSWindow, content: some View) {
                self.host = host
                super.init(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: true)
                isOpaque = false
                backgroundColor = .clear
                hasShadow = false
                ignoresMouseEvents = true
                isReleasedWhenClosed = false
                animationBehavior = .none
                collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle]
                setAccessibilityElement(false)
                contentView = NSHostingView(rootView: content.accessibilityHidden(true))
                followHost()
            }

            override package var canBecomeKey: Bool {
                false
            }

            override package var canBecomeMain: Bool {
                false
            }

            /// Covers the host's content view, and is ordered in above the host while the host is
            /// on screen. A host not on screen yet (a window in a test) leaves it out of the
            /// window list.
            package func followHost() {
                guard let host, let frame = Self.contentFrameOnScreen(of: host) else { return }
                if self.frame != frame { setFrame(frame, display: false) }
                guard host.isVisible, parent == nil else { return }
                host.addChildWindow(self, ordered: .above)
                // The drawer's panel, a child of the same window, stays above what plugins draw.
                for panel in host.childWindows ?? [] where panel is DrawerChildPanel {
                    panel.order(.above, relativeTo: windowNumber)
                }
            }

            /// `rect`, in the host window's coordinates, in this window's content: points from its
            /// top-leading corner.
            ///
            /// - Parameter rect: A rectangle in the host window's base coordinates.
            /// - Returns: The same rectangle in the content `init(over:content:)` was given.
            package func convert(fromHost rect: CGRect) -> CGRect {
                guard let host, let contentView else { return .zero }
                return contentView.convert(convertFromScreen(host.convertToScreen(rect)), from: nil)
            }

            /// `point`, in the host window's coordinates, in this window's content.
            ///
            /// - Parameter point: A point in the host window's base coordinates.
            /// - Returns: The same point in the content `init(over:content:)` was given.
            package func convert(fromHost point: CGPoint) -> CGPoint {
                convert(fromHost: CGRect(origin: point, size: .zero)).origin
            }

            /// Takes the window off screen and away from its host.
            package func remove() {
                host?.removeChildWindow(self)
                orderOut(nil)
            }

            /// The host's content view on screen.
            private static func contentFrameOnScreen(of host: NSWindow) -> CGRect? {
                guard let contentView = host.contentView else { return nil }
                return host.convertToScreen(contentView.convert(contentView.bounds, to: nil))
            }
        }

        /// Whether `window` is the drawer's own (its panel or an overlay), which a plugin that
        /// draws or inspects the app's windows leaves out.
        @MainActor package func isDebugDrawerWindow(_ window: NSWindow) -> Bool {
            window is DrawerChildPanel || window is DrawerOverlayWindow
        }
    #else
        // Mac Catalyst too: a Catalyst scene's windows share its Mac window, so a window of the
        // scene's own at a higher level draws over the app's there as on iOS (DrawerSceneWindow).
        import UIKit

        /// A transparent window over every window of a scene, under the drawer's, that draws
        /// `content` and takes no touch.
        ///
        /// It has no root view controller, so the status bar's style and the supported
        /// orientations stay the app's windows'. ``isDebugDrawerWindow(_:)`` is `true` for it.
        package final class DrawerOverlayWindow: UIWindow {
            /// Above alerts, so it draws over them, and under the drawer's window.
            package static let level = UIWindow.Level(rawValue: UIWindow.Level.alert.rawValue + 0.5)

            private let hosting: UIViewController

            /// A window covering `scene` drawing `content`, laid out from the window's
            /// top-leading corner, in points; with no scene, a window of zero size until it is
            /// given a frame.
            ///
            /// - Parameters:
            ///   - scene: The app's scene.
            ///   - content: What to draw over it.
            package init(scene: UIWindowScene?, content: some View) {
                let hosting = UIHostingController(rootView: content.accessibilityHidden(true))
                hosting.safeAreaRegions = []
                hosting.view.backgroundColor = .clear
                hosting.view.isUserInteractionEnabled = false
                self.hosting = hosting
                if let scene {
                    super.init(windowScene: scene)
                } else {
                    super.init(frame: .zero)
                }
                windowLevel = Self.level
                backgroundColor = .clear
                isUserInteractionEnabled = false
                accessibilityElementsHidden = true
                // A plain subview, not the root view controller: the topmost window's root view
                // controller decides the status bar and the orientations, which stay the app's.
                hosting.view.frame = bounds
                hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                addSubview(hosting.view)
                isHidden = false
            }

            @available(*, unavailable)
            required init?(coder _: NSCoder) {
                fatalError("The overlay window is made in code.")
            }

            /// Takes no touch, so UIKit offers each to the windows below.
            override package func hitTest(_: CGPoint, with _: UIEvent?) -> UIView? {
                nil
            }

            /// Takes the window off screen.
            package func remove() {
                isHidden = true
            }
        }
    #endif
#endif
