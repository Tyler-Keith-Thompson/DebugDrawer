// The Mac and iOS (Mac Catalyst too, whose scenes are UIKit's) draw the drawer in a window of its
// own, attached to the window a view is in, and list a view's local plugins in that window's
// drawer; the other platforms have one drawer, in the app's window (DebugDrawerModifier).
#if DEBUG && (os(macOS) || os(iOS))
    import SwiftUI

    // SwiftUI has no public environment value for the NSWindow or UIWindowScene a view is hosted
    // in (`openWindow` and `scenePhase` name no window), so an empty platform view reads it: AppKit
    // and UIKit call `viewDidMoveToWindow` and `didMoveToWindow` the moment a view joins a window,
    // where `window` (and on iOS its `windowScene`) is set, with no waiting for a frame or a delay.

    /// An empty platform view that tells `didMove` the window (on iOS, the scene) it is added to,
    /// each time it is added to one. It takes no clicks or touches and no space and is hidden from
    /// accessibility.
    struct DrawerWindowReader: View {
        #if os(macOS)
            let didMove: @MainActor (NSWindow) -> Void
        #else
            let didMove: @MainActor (UIWindowScene) -> Void
        #endif

        var body: some View {
            DrawerWindowReaderRepresentable(didMove: didMove)
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    #if os(macOS)
        private struct DrawerWindowReaderRepresentable: NSViewRepresentable {
            let didMove: @MainActor (NSWindow) -> Void

            func makeNSView(context _: Context) -> DrawerWindowReaderView {
                DrawerWindowReaderView(didMove: didMove)
            }

            func updateNSView(_ view: DrawerWindowReaderView, context _: Context) {
                view.didMove = didMove
            }
        }

        private final class DrawerWindowReaderView: NSView {
            var didMove: @MainActor (NSWindow) -> Void

            init(didMove: @escaping @MainActor (NSWindow) -> Void) {
                self.didMove = didMove
                super.init(frame: .zero)
            }

            @available(*, unavailable)
            required init?(coder _: NSCoder) {
                fatalError("Made in code.")
            }

            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                guard let window else { return }
                didMove(window)
            }

            override func hitTest(_: NSPoint) -> NSView? {
                nil
            }
        }
    #else
        private struct DrawerWindowReaderRepresentable: UIViewRepresentable {
            let didMove: @MainActor (UIWindowScene) -> Void

            func makeUIView(context _: Context) -> DrawerWindowReaderView {
                DrawerWindowReaderView(didMove: didMove)
            }

            func updateUIView(_ view: DrawerWindowReaderView, context _: Context) {
                view.didMove = didMove
            }
        }

        private final class DrawerWindowReaderView: UIView {
            var didMove: @MainActor (UIWindowScene) -> Void

            init(didMove: @escaping @MainActor (UIWindowScene) -> Void) {
                self.didMove = didMove
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
                didMove(scene)
            }
        }
    #endif
#endif
