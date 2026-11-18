#if DEBUG && (os(macOS) || os(iOS))
    import SwiftUI

    /// An empty view behind the content `.debugGrid()` is applied to, sized to it, that tells the
    /// View Inspector where the grid goes. It draws nothing and takes no clicks or touches: the
    /// grid itself is drawn in the drawer's overlay window, not in the app's.
    struct GridProbe: View {
        let controller: ViewBorderController

        var body: some View {
            GridProbeRepresentable(controller: controller)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    #if os(macOS)
        private struct GridProbeRepresentable: NSViewRepresentable {
            let controller: ViewBorderController

            func makeNSView(context _: Context) -> GridProbeView {
                let view = GridProbeView()
                controller.addGridProbe(view)
                return view
            }

            func updateNSView(_: GridProbeView, context _: Context) {}
        }

        /// The platform view behind ``GridProbe``, whose frame in its window is the grid's.
        final class GridProbeView: NSView {
            override func hitTest(_: NSPoint) -> NSView? {
                nil
            }

            override func isAccessibilityElement() -> Bool {
                false
            }
        }
    #else
        private struct GridProbeRepresentable: UIViewRepresentable {
            let controller: ViewBorderController

            func makeUIView(context _: Context) -> GridProbeView {
                let view = GridProbeView()
                view.isUserInteractionEnabled = false
                view.isAccessibilityElement = false
                controller.addGridProbe(view)
                return view
            }

            func updateUIView(_: GridProbeView, context _: Context) {}
        }

        /// The platform view behind ``GridProbe``, whose frame in its window is the grid's.
        final class GridProbeView: UIView {}
    #endif
#endif
