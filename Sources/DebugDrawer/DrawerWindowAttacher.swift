// The Mac and iOS (Mac Catalyst too, whose scenes are UIKit's) draw the drawer in a window of its
// own; the other platforms draw it in the app's (DebugDrawerModifier).
#if DEBUG && (os(macOS) || os(iOS))
    import SwiftUI

    /// An empty platform view that attaches the drawer to the window (on iOS, the scene) it is
    /// added to, the moment it is: no waiting for a frame or a delay. It takes no touches and no
    /// space and is hidden from accessibility.
    struct DrawerWindowAttacher: View {
        let drawer: DebugDrawer

        var body: some View {
            DrawerWindowAttacherRepresentable(drawer: drawer)
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    #if os(macOS)
        private struct DrawerWindowAttacherRepresentable: NSViewRepresentable {
            let drawer: DebugDrawer

            func makeNSView(context _: Context) -> DrawerWindowAttacherView {
                DrawerWindowAttacherView(drawer: drawer)
            }

            func updateNSView(_: DrawerWindowAttacherView, context _: Context) {}
        }

        private final class DrawerWindowAttacherView: NSView {
            let drawer: DebugDrawer

            init(drawer: DebugDrawer) {
                self.drawer = drawer
                super.init(frame: .zero)
            }

            @available(*, unavailable)
            required init?(coder _: NSCoder) {
                fatalError("Made in code.")
            }

            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                guard let window else { return }
                drawer.attach(to: window)
            }

            override func hitTest(_: NSPoint) -> NSView? {
                nil
            }
        }
    #else
        private struct DrawerWindowAttacherRepresentable: UIViewRepresentable {
            let drawer: DebugDrawer

            func makeUIView(context _: Context) -> DrawerWindowAttacherView {
                DrawerWindowAttacherView(drawer: drawer)
            }

            func updateUIView(_: DrawerWindowAttacherView, context _: Context) {}
        }

        private final class DrawerWindowAttacherView: UIView {
            let drawer: DebugDrawer

            init(drawer: DebugDrawer) {
                self.drawer = drawer
                super.init(frame: .zero)
                isUserInteractionEnabled = false
                isAccessibilityElement = false
            }

            @available(*, unavailable)
            required init?(coder _: NSCoder) {
                fatalError("Made in code.")
            }

            override func didMoveToWindow() {
                super.didMoveToWindow()
                guard let scene = window?.windowScene else { return }
                drawer.attach(to: scene)
            }
        }
    #endif
#endif
