#if DEBUG
    import CoreGraphics
    import DebugDrawer
    import QuartzCore
    #if os(macOS)
        import AppKit
    #elseif os(iOS)
        import UIKit
    #endif

    /// The windows a recording draws, each frame, with the drawer's layers hidden
    /// (`DrawerChromeLayers`): on iOS every window of the scene that was in front when recording
    /// started, in window-level order, so sheets and alerts show, but not the drawer's own window;
    /// on macOS the content of the window that was main, which the drawer's panel, a window of its
    /// own, is not part of.
    ///
    /// Drawn with `CALayer.render(in:)`, in process: no ReplayKit or ScreenCaptureKit, so no
    /// permission prompt, and the drawer can be left out while it stays on screen. The render is of
    /// the model tree, so a Core Animation transition (a UIKit push, a sheet sliding up) shows its
    /// end at once, and content drawn outside the layer tree (Metal, video, a web view's own
    /// process) may come out blank.
    @MainActor
    final class RecordedWindows {
        #if os(macOS)
            private weak var window: NSWindow?

            /// The main window, or the key one, or `nil` when the app shows none.
            convenience init?() {
                guard let window = NSApp?.mainWindow ?? debugDrawerAppKeyWindow else { return nil }
                self.init(window: window)
            }

            /// `window`, or `nil` when its content view has no layer to draw.
            init?(window: NSWindow) {
                guard window.contentView?.layer != nil else { return nil }
                self.window = window
            }

            /// The window, drawn as it is now with the drawer's layers hidden and `touches` (in
            /// points from the window's top-leading corner) circled, or `nil` once it has closed.
            func render(touches: [CGPoint]) -> CGImage? {
                guard let view = window?.contentView, let layer = view.layer else { return nil }
                let size = view.bounds.size
                let scale = RecordingScale.scale(for: size, screenScale: window?.backingScaleFactor ?? 2)
                return Self.image(size: size, scale: scale) { context in
                    // A flipped content view (NSHostingView is one) lays its layers out from the
                    // top-leading corner, so the context is flipped to match; an unflipped one
                    // already matches Core Graphics.
                    if layer.isGeometryFlipped {
                        context.translateBy(x: 0, y: size.height)
                        context.scaleBy(x: 1, y: -1)
                    }
                    DrawerChromeLayers.hidden(in: layer) { layer.render(in: context) }
                    TouchIndicator.draw(at: touches, in: context)
                }
            }

            /// A display link on the window's screen.
            func displayLink(target: Any, selector: Selector) -> CADisplayLink? {
                window?.contentView?.displayLink(target: target, selector: selector)
            }
        #elseif os(iOS)
            private weak var scene: UIWindowScene?

            /// The scene in front, or `nil` when the app shows none.
            convenience init?() {
                let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else { return nil }
                self.init(scene: scene)
            }

            /// `scene`, or `nil` when it has no window.
            init?(scene: UIWindowScene) {
                guard !scene.windows.isEmpty else { return nil }
                self.scene = scene
            }

            /// The scene's visible windows, lowest level first, without the drawer's own.
            var windows: [UIWindow] {
                (scene?.windows ?? [])
                    .filter { !$0.isHidden && $0.alpha > 0 && $0.bounds.width > 0 && $0.bounds.height > 0 }
                    .filter { !isDebugDrawerWindow($0) }
                    .enumerated()
                    .sorted { ($0.element.windowLevel.rawValue, $0.offset) < ($1.element.windowLevel.rawValue, $1.offset) }
                    .map(\.element)
            }

            /// The scene, drawn as it is now with the drawer's layers hidden and `touches` (in
            /// points in the scene) circled, or `nil` once it has no window.
            func render(touches: [CGPoint]) -> CGImage? {
                let windows = windows
                guard let scene, let canvas = windows.first(where: \.isKeyWindow) ?? windows.first else { return nil }
                let size = canvas.bounds.size
                let scale = RecordingScale.scale(for: size, screenScale: scene.screen.scale)
                return Self.image(size: size, scale: scale) { context in
                    // UIKit draws from the top-leading corner.
                    context.translateBy(x: 0, y: size.height)
                    context.scaleBy(x: 1, y: -1)
                    for window in windows {
                        context.saveGState()
                        context.translateBy(x: window.frame.minX - canvas.frame.minX, y: window.frame.minY - canvas.frame.minY)
                        DrawerChromeLayers.hidden(in: window.layer) { window.layer.render(in: context) }
                        context.restoreGState()
                    }
                    TouchIndicator.draw(at: touches, in: context)
                }
            }

            /// A display link on the main screen.
            func displayLink(target: Any, selector: Selector) -> CADisplayLink? {
                CADisplayLink(target: target, selector: selector)
            }
        #endif

        /// An image `size` points across at `scale` pixels a point, white where nothing is drawn,
        /// with `draw` given a context in points.
        private static func image(size: CGSize, scale: CGFloat, draw: (CGContext) -> Void) -> CGImage? {
            let width = Int((size.width * scale).rounded())
            let height = Int((size.height * scale).rounded())
            guard width > 0, height > 0,
                  let context = CGContext(
                      data: nil,
                      width: width,
                      height: height,
                      bitsPerComponent: 8,
                      bytesPerRow: 0,
                      space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
                  )
            else { return nil }
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.scaleBy(x: scale, y: scale)
            draw(context)
            return context.makeImage()
        }
    }
#endif
