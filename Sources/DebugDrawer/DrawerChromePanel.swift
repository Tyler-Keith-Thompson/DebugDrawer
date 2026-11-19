#if DEBUG && os(macOS)
    import AppKit
    import SwiftUI

    // The HUD and the toast each in a child window of the app's window, as the panel is
    // (DrawerChildPanel), rather than in its root view: `attach(to:)` then shows them over an
    // AppKit window with no SwiftUI view, they stay above the window's sheets and alerts, and a
    // window that has both `debugDrawer()` and `attach(to:)` draws them once. Each window is just
    // the size of what it draws, so a click anywhere else lands in the app's window: AppKit gives
    // a window every click inside its frame, and offers no hit test that passes one on to the
    // window below. So the HUD's card moves its window as it is dragged. Each stays ordered in,
    // so SwiftUI keeps its view up to date, and with nothing to draw it is transparent and
    // ignores the mouse.

    /// A borderless child window over the app's window drawing the drawer's HUD card or its toast,
    /// sized to it: the HUD at its saved corner, the toast at the top trailing corner.
    final class DrawerChromePanel: NSPanel {
        /// What a panel draws.
        enum Role {
            /// The pinned plugins' HUD card, which the developer drags anywhere in the window.
            case hud
            /// A plugin's toast, at the window's top trailing corner.
            case toast
        }

        let role: Role
        /// The window the panel draws over.
        private(set) weak var host: NSWindow?
        private let drawer: DebugDrawer
        /// The size of what the panel draws, its margin left out; zero while it draws nothing.
        private(set) var contentSize = CGSize.zero
        /// Where a drag of the HUD started: the mouse, in screen coordinates, and the panel's
        /// frame then.
        private var dragStart: (mouse: CGPoint, frame: CGRect)?
        private var observers: [any NSObjectProtocol] = []

        init(role: Role, host: NSWindow, drawer: DebugDrawer) {
            self.role = role
            self.host = host
            self.drawer = drawer
            super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
            isOpaque = false
            backgroundColor = .clear
            // The window draws the shadow, around the card's rounded shape: the SwiftUI one is
            // clipped at the window's edges.
            hasShadow = true
            isReleasedWhenClosed = false
            worksWhenModal = true
            animationBehavior = .none
            collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle]
            contentView = hostingContainer()
            show(nothing: true)
            host.addChildWindow(self, ordered: .above)
            updateLevel()
            observe(host)
        }

        override var canBecomeKey: Bool {
            false
        }

        override var canBecomeMain: Bool {
            false
        }

        /// What the panel draws, in a view laid out at its own size, offset by the toast's margin
        /// so the window holds only the toast.
        private func hostingContainer() -> NSView {
            let container = NSView()
            let root: AnyView = switch role {
            case .hud: AnyView(DrawerHUDPanelContent(drawer: drawer, panel: self))
            case .toast: AnyView(DrawerToastPanelContent(drawer: drawer, panel: self))
            }
            let hosting = DrawerChromeHostingView(rootView: root)
            // The panel sizes itself from what SwiftUI reports, not from the view's constraints.
            hosting.sizingOptions = []
            container.addSubview(hosting)
            return container
        }

        /// The margin the toast's view draws around it, which the panel leaves out.
        private var margin: CGFloat {
            role == .toast ? DrawerToastView.margin : 0
        }

        /// SwiftUI laid out what the panel draws at `size`, its margin included; zero when it
        /// draws nothing.
        func contentDidResize(_ size: CGSize) {
            // Whole points, as AppKit rounds a window's frame.
            let width = (size.width - margin * 2).rounded(.up)
            let height = (size.height - margin * 2).rounded(.up)
            let inner = width > 0 && height > 0 ? CGSize(width: width, height: height) : .zero
            if let hosting = contentView?.subviews.first {
                hosting.frame = CGRect(x: -margin, y: -margin, width: size.width, height: size.height)
            }
            contentSize = inner
            show(nothing: inner == .zero)
            updateFrame()
        }

        /// A panel with nothing to draw is clear and lets every click through.
        private func show(nothing: Bool) {
            alphaValue = nothing ? 0 : 1
            ignoresMouseEvents = nothing
        }

        /// Places the panel over its window: the HUD at its saved corner, the toast at the top
        /// trailing corner.
        func updateFrame() {
            guard let host, dragStart == nil else { return }
            let content = host.convertToScreen(host.contentLayoutRect)
            let frame = switch role {
            case .hud: Self.hudFrame(origin: drawer.hudLayout.origin, size: contentSize, in: content)
            case .toast: Self.toastFrame(size: contentSize, in: content)
            }
            if self.frame != frame { setFrame(frame, display: true) }
            invalidateShadow()
        }

        /// The HUD's card in screen coordinates: its corner, kept so the card stays inside the
        /// window's content.
        ///
        /// - Parameters:
        ///   - origin: The card's top-leading corner from the content's, or `nil` for the default.
        ///   - size: The card's size.
        ///   - content: The window's content area, in screen coordinates.
        /// - Returns: The panel's frame.
        static func hudFrame(origin: CGPoint?, size: CGSize, in content: CGRect) -> CGRect {
            let corner = (origin ?? DrawerHUDView.defaultOrigin).kept(showing: size, in: content.size)
            return CGRect(x: content.minX + corner.x, y: content.maxY - corner.y - size.height, width: size.width, height: size.height)
        }

        /// The HUD card's top-leading corner from the content's, for a panel at `frame`.
        ///
        /// - Parameters:
        ///   - frame: The panel's frame, in screen coordinates.
        ///   - content: The window's content area, in screen coordinates.
        /// - Returns: The corner ``DebugDrawer/moveHUD(to:)`` saves.
        static func hudOrigin(of frame: CGRect, in content: CGRect) -> CGPoint {
            CGPoint(x: frame.minX - content.minX, y: content.maxY - frame.maxY)
        }

        /// The toast in screen coordinates: at the content's top trailing corner, inset by the
        /// toast's margin.
        ///
        /// - Parameters:
        ///   - size: The toast's size, without its margin.
        ///   - content: The window's content area, in screen coordinates.
        /// - Returns: The panel's frame.
        static func toastFrame(size: CGSize, in content: CGRect) -> CGRect {
            let margin = DrawerToastView.margin
            return CGRect(
                x: content.maxX - margin - size.width, y: content.maxY - margin - size.height,
                width: size.width, height: size.height
            )
        }

        /// Moves the HUD's panel with the mouse, kept inside the window's content.
        ///
        /// The drag gesture's translation is measured in the panel, which moves under it, so the
        /// panel follows the mouse on screen instead.
        ///
        /// - Parameters:
        ///   - translation: The gesture's translation when it began to move, in points, y down.
        ///   - mouse: Where the mouse is now, in screen coordinates.
        func drag(translation: CGSize, mouse: CGPoint) {
            guard let host else { return }
            let start = dragStart ?? (
                mouse: CGPoint(x: mouse.x - translation.width, y: mouse.y + translation.height),
                frame: frame
            )
            dragStart = start
            let content = host.convertToScreen(host.contentLayoutRect)
            let moved = start.frame.offsetBy(dx: mouse.x - start.mouse.x, dy: mouse.y - start.mouse.y)
            let origin = Self.hudOrigin(of: moved, in: content)
            setFrame(Self.hudFrame(origin: origin, size: frame.size, in: content), display: true)
        }

        /// Saves where the HUD was dropped.
        func endDrag() {
            guard let host, dragStart != nil else { return }
            dragStart = nil
            let content = host.convertToScreen(host.contentLayoutRect)
            drawer.moveHUD(to: Self.hudOrigin(of: frame, in: content))
        }

        private func updateLevel() {
            guard let host else { return }
            level = DrawerChildPanel.level(appIsActive: NSApplication.shared.isActive, hostIsMain: host.isMainWindow, host: host)
        }

        /// Follows the window's size, its main status and the app's activation, and leaves the
        /// window when it closes.
        private func observe(_ host: NSWindow) {
            let center = NotificationCenter.default
            let resize: [Notification.Name] = [
                NSWindow.didResizeNotification, NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification
            ]
            for name in resize {
                observers.append(center.addObserver(forName: name, object: host, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.updateFrame() }
                })
            }
            let levels: [(Notification.Name, AnyObject?)] = [
                (NSWindow.didBecomeMainNotification, host),
                (NSWindow.didResignMainNotification, host),
                (NSApplication.didBecomeActiveNotification, nil),
                (NSApplication.didResignActiveNotification, nil)
            ]
            for (name, object) in levels {
                observers.append(center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.updateLevel() }
                })
            }
            observers.append(center.addObserver(forName: NSWindow.willCloseNotification, object: host, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.host?.removeChildWindow(self)
                    self.orderOut(nil)
                }
            })
        }

        isolated deinit {
            observers.forEach(NotificationCenter.default.removeObserver)
        }
    }

    /// A hosting view that takes the first click in a window that isn't key, as the panel never is.
    private final class DrawerChromeHostingView: NSHostingView<AnyView> {
        override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
            true
        }
    }

    /// The HUD's card alone, at its own size, which drags its panel.
    private struct DrawerHUDPanelContent: View {
        @ObservedObject var drawer: DebugDrawer
        weak var panel: DrawerChromePanel?

        var body: some View {
            ZStack {
                let readouts = drawer.hudPlugins
                if !readouts.isEmpty {
                    DrawerHUDCard(readouts: readouts) { drawer.toggleHUD(forPlugin: $0) }
                        .opacity(drawer.isHUDHidden ? 0 : 1)
                        .environment(\.showingDrawer, drawer)
                        .gesture(
                            DragGesture()
                                .onChanged { panel?.drag(translation: $0.translation, mouse: NSEvent.mouseLocation) }
                                .onEnded { _ in panel?.endDrag() }
                        )
                }
            }
            .fixedSize()
            .onGeometryChange(for: CGSize.self, of: \.size) { panel?.contentDidResize($0) }
            .onChange(of: drawer.hudLayout.origin) { panel?.updateFrame() }
        }
    }

    /// The toast alone, with its margin, as wide as it is drawn over a window and as tall as its
    /// message needs; no height while there is none.
    private struct DrawerToastPanelContent: View {
        @ObservedObject var drawer: DebugDrawer
        weak var panel: DrawerChromePanel?

        var body: some View {
            DrawerToastLayer(drawer: drawer)
                .frame(width: DrawerToastView.maxWidth + DrawerToastView.margin * 2)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGSize.self, of: \.size) { panel?.contentDidResize($0) }
        }
    }
#endif
