// The views are hosted on the Mac.
#if os(macOS)
    import AppKit
    @testable import DebugDrawer
    import SwiftUI
    import Testing

    // debugDrawer() shows the shared drawer, attaching each window it is in, so these tests stay on
    // it, in the serialized suite of the shared drawer's tests.
    extension SharedDrawerTests {
        @MainActor
        @Suite
        struct DrawerChromeBoundaryTests {
            @Test("A view under .debugDrawer() has the chrome start layer after the app's content and the end layer after it, once each")
            func boundary() {
                let host = NSHostingView(rootView: Color.red.frame(width: 400, height: 300).debugDrawer())
                let window = NSWindow(
                    contentRect: CGRect(x: 0, y: 0, width: 400, height: 300),
                    styleMask: .borderless, backing: .buffered, defer: false
                )
                window.contentView = host
                host.frame = CGRect(x: 0, y: 0, width: 400, height: 300)
                host.layoutSubtreeIfNeeded()
                host.displayIfNeeded()
                // The views' layers join the host's layer tree when the transaction commits.
                CATransaction.flush()
                let expected = [debugDrawerChromeStartLayerName, debugDrawerChromeEndLayerName]

                var names: [String] = []
                func visit(_ layer: CALayer) {
                    if let name = layer.name, expected.contains(name) { names.append(name) }
                    for sublayer in layer.sublayers ?? [] {
                        visit(sublayer)
                    }
                }
                if let layer = host.layer { visit(layer) }

                #expect(names == expected)
            }

            @Test("The boundary takes no clicks: a hit test through it reaches the app")
            func takesNoClicks() {
                let host = NSHostingView(rootView: Color.red.frame(width: 400, height: 300).debugDrawer())
                let window = NSWindow(
                    contentRect: CGRect(x: 0, y: 0, width: 400, height: 300),
                    styleMask: .borderless, backing: .buffered, defer: false
                )
                window.contentView = host
                host.frame = CGRect(x: 0, y: 0, width: 400, height: 300)
                host.layoutSubtreeIfNeeded()

                let hit = host.hitTest(CGPoint(x: 200, y: 150))

                #expect(hit?.layer?.name != debugDrawerChromeStartLayerName)
                #expect(hit?.layer?.name != debugDrawerChromeEndLayerName)
            }
        }
    }
#endif
