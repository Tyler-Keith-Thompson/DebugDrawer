/// The name of the empty layer just before the drawer's own interface (the HUD, the panel and
/// the toast) in the window's layer tree; ``debugDrawerChromeEndLayerName`` names the one just
/// after it.
///
/// In painter's order, every layer between the two belongs to the drawer, so a plugin that
/// renders the window in process (a screen recorder) can leave the drawer out by hiding them for
/// the length of the render.
public let debugDrawerChromeStartLayerName = "com.debugdrawer.chrome.start"

/// The name of the empty layer just after the drawer's own interface in the window's layer
/// tree; see ``debugDrawerChromeStartLayerName``.
public let debugDrawerChromeEndLayerName = "com.debugdrawer.chrome.end"

#if DEBUG
    import SwiftUI

    // MARK: - Chrome boundary

    // Two empty platform views bracket the drawer's own interface (the HUD, the panel and the
    // toast) in the window's layer tree. SwiftUI draws content that comes after a platform view in
    // layers above that view's, so in painter's order every layer between the two is the drawer's
    // and every layer outside them is the app's. A recorder that renders the window in process can
    // hide the layers between them for the length of one render, which no commit ever shows, and so
    // record the app without the drawer while the drawer stays on screen. On the Mac and iOS the
    // panel, the HUD and the toast are each in a window of the drawer's own (DrawerChildPanel,
    // DrawerSceneWindow, DrawerChromePanel, DrawerChromeWindow), which a capture of the app's
    // window leaves out anyway, so there the markers hold nothing between them; they stay so
    // anything of the drawer's drawn in the app's window later is left out too. Rejected: naming the drawer's layers by SwiftUI's internal
    // classes (undocumented, and they change between releases).

    /// An empty platform view with a named layer, which takes no touches and no space and is hidden
    /// from accessibility. Platforms with no recorder draw nothing.
    struct DrawerChromeBoundaryMarker: View {
        let layerName: String

        var body: some View {
            #if os(macOS) || os(iOS)
                DrawerChromeBoundaryLayer(layerName: layerName)
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            #else
                EmptyView()
            #endif
        }
    }

    #if os(macOS)
        private struct DrawerChromeBoundaryLayer: NSViewRepresentable {
            let layerName: String

            func makeNSView(context _: Context) -> NSView {
                let view = DrawerChromeBoundaryView()
                view.wantsLayer = true
                view.layer?.name = layerName
                return view
            }

            func updateNSView(_: NSView, context _: Context) {}
        }

        /// A view no click lands on.
        private final class DrawerChromeBoundaryView: NSView {
            override func hitTest(_: NSPoint) -> NSView? {
                nil
            }
        }
    #elseif os(iOS)
        // Mac Catalyst hosts SwiftUI in UIViews, so the marker works there as on iOS.
        private struct DrawerChromeBoundaryLayer: UIViewRepresentable {
            let layerName: String

            func makeUIView(context _: Context) -> UIView {
                let view = UIView()
                view.isUserInteractionEnabled = false
                view.isAccessibilityElement = false
                view.layer.name = layerName
                return view
            }

            func updateUIView(_: UIView, context _: Context) {}
        }
    #endif
#endif
