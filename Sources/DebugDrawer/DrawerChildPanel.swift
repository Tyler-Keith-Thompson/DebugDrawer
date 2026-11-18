#if DEBUG && os(macOS)
    import AppKit
    import SwiftUI

    // A child window of the app's window, rather than an overlay in its root view: a sheet is a
    // window of its own over the app's, so it covers an overlay in the root view. As a child, the
    // panel moves with its window and is ordered above it; it covers only its own rectangle, so a
    // click anywhere else reaches the app's window. A child window's level is its parent's unless
    // set after it is added: at that level a sheet or a sheet alert, ordered in later, covers it.
    // The panel takes the level just above `.modalPanel` instead, over sheets, sheet alerts and an
    // app-modal NSAlert (level 8), and `worksWhenModal`, so its controls take clicks while such an
    // alert runs. That level would also float it over the app's other windows and other apps',
    // so it holds it only while its window is the active app's main window, and otherwise drops
    // to its window's level, still ordered above it.

    /// The drawer's panel on the Mac: a borderless child window along the trailing edge of the
    /// window it is attached to, inside the content area, hosting the panel's view.
    final class DrawerChildPanel: NSPanel, DrawerPresentationHost {
        /// Over sheets and an app-modal alert.
        static let raisedLevel = NSWindow.Level(rawValue: NSWindow.Level.modalPanel.rawValue + 1)
        /// The space between the panel and the window's content edges.
        static let margin: CGFloat = 8

        let presentation: DrawerPresentation
        /// The window the panel is attached to.
        private(set) weak var host: NSWindow?
        private var observers: [any NSObjectProtocol] = []

        init(host: NSWindow, drawer: DebugDrawer, presentation: DrawerPresentation) {
            self.host = host
            self.presentation = presentation
            super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
            isOpaque = false
            backgroundColor = .clear
            // The window draws the shadow, around the panel's rounded shape: a SwiftUI shadow
            // would be clipped at the window's edges.
            hasShadow = true
            isReleasedWhenClosed = false
            worksWhenModal = true
            animationBehavior = .none
            contentView = NSHostingView(rootView: DebugDrawerOverlay(drawer: drawer, presentation: presentation)
                .accessibilityIdentifier(debugDrawerOverlayIdentifier))
            presentation.host = self
            presentation.layout = DrawerPanelLayout(windowWidth: host.contentLayoutRect.width)
            observe(host)
        }

        override var canBecomeKey: Bool {
            true
        }

        override var canBecomeMain: Bool {
            false
        }

        /// Whether the panel is on screen beside its window.
        var isShown: Bool {
            parent != nil && isVisible
        }

        func drawerWillShow() {
            show()
        }

        /// Takes the panel off screen, first handing keyboard focus back to its window.
        func drawerDidHide() {
            guard !presentation.isOpen else { return }
            if isKeyWindow { host?.makeKey() }
            host?.removeChildWindow(self)
            orderOut(nil)
        }

        /// Orders the panel in beside its window and makes it key, so the drawer's keyboard
        /// shortcuts work at once; the window stays main. A window not on screen yet (the drawer
        /// opened as the app launched) brings the panel in with it when it is ordered in.
        private func show() {
            guard let host, !isShown else { return }
            if parent == nil { host.addChildWindow(self, ordered: .above) }
            updateLevel()
            updateFrame()
            guard host.isVisible else { return }
            orderFront(nil)
            makeKey()
        }

        /// The panel's frame: the window's content area, less the title bar and a margin, at the
        /// trailing edge for a regular panel, or across the whole width for a compact one.
        static func frame(in content: CGRect, layout: DrawerPanelLayout) -> CGRect {
            let height = max(0, content.height - margin * 2)
            switch layout {
            case .regular:
                let width = DrawerPanelLayout.regularWidth
                return CGRect(x: content.maxX - margin - width, y: content.minY + margin, width: width, height: height)
            case .compact:
                return CGRect(x: content.minX + margin, y: content.minY + margin, width: max(0, content.width - margin * 2), height: height)
            }
        }

        private func updateFrame() {
            guard let host else { return }
            let layout = DrawerPanelLayout(windowWidth: host.contentLayoutRect.width)
            if presentation.layout != layout { presentation.layout = layout }
            setFrame(Self.frame(in: host.convertToScreen(host.contentLayoutRect), layout: layout), display: true)
            invalidateShadow()
        }

        private func updateLevel() {
            guard let host, parent != nil else { return }
            level = Self.level(appIsActive: NSApplication.shared.isActive, hostIsMain: host.isMainWindow, host: host)
        }

        /// The panel's level: over sheets and an app-modal alert while its window is the active
        /// app's main window, and otherwise its window's, so it floats over no other window.
        ///
        /// - Parameters:
        ///   - appIsActive: Whether the app is the active one.
        ///   - hostIsMain: Whether the panel's window is the app's main window.
        ///   - host: The panel's window.
        /// - Returns: The level to give the panel.
        static func level(appIsActive: Bool, hostIsMain: Bool, host: NSWindow) -> NSWindow.Level {
            appIsActive && hostIsMain ? raisedLevel : host.level
        }

        /// Follows the window's size, its main status and the app's activation, and detaches when
        /// the window closes.
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
                    DebugDrawer.shared.detach(self.presentation)
                }
            })
        }

        isolated deinit {
            observers.forEach(NotificationCenter.default.removeObserver)
        }
    }
#endif
