#if DEBUG
    #if os(macOS)
        import AppKit
    #elseif os(iOS)
        import UIKit
    #endif

    /// A window's drawer: its state and, on the Mac and iOS, the windows it, its HUD and its toast
    /// are drawn in.
    @MainActor
    struct DrawerAttachment {
        let presentation: DrawerPresentation
        #if os(macOS)
            /// The window the drawer is attached to.
            weak var window: NSWindow?
            let panel: DrawerChildPanel
            /// The HUD's card, over the window.
            let hud: DrawerChromePanel
            /// The toast, over the window.
            let toast: DrawerChromePanel
        #elseif os(iOS)
            /// The scene the drawer is attached to.
            weak var scene: UIWindowScene?
            let window: DrawerSceneWindow
            /// The HUD and the toast, over the scene's windows.
            let chrome: DrawerChromeWindow
        #endif
    }

    extension DebugDrawer {
        #if os(macOS)
            /// Shows the drawer over `window`, in a panel of its own along the window's trailing
            /// edge, above its sheets and alerts, with the HUD and the toasts over the window.
            ///
            /// `debugDrawer()` calls this for the window its view is in; call it yourself from an
            /// AppKit app, once the window exists. Attaching a window twice does nothing; a sheet
            /// attaches the window it is on. The drawer's open state belongs to the window:
            /// ``isOpen`` and ``toggle()`` act on the key window's, and ``toggle(in:)`` on the
            /// window given. It lists the global plugins and the local plugins of the window's own
            /// views. The drawer detaches when the window closes. In release builds it does nothing.
            ///
            /// - Parameter window: The app's window.
            public func attach(to window: NSWindow) {
                let host = Self.appWindow(for: window)
                pruneAttachments()
                guard !attachments.contains(where: { $0.window === host }) else { return }
                let presentation = adoptDetachedState()
                presentation.scope = Self.scope(of: host)
                let panel = DrawerChildPanel(host: host, drawer: self, presentation: presentation)
                attachments.append(DrawerAttachment(
                    presentation: presentation,
                    window: host,
                    panel: panel,
                    hud: DrawerChromePanel(role: .hud, host: host, drawer: self),
                    toast: DrawerChromePanel(role: .toast, host: host, drawer: self)
                ))
                if presentation.isOpen { panel.drawerWillShow() }
                presentationDidChange()
            }

            /// Opens the drawer in `window` if it is closed there and closes it if it is open,
            /// whichever window is key; the other windows' drawers stay as they are.
            ///
            /// A window not attached yet is attached first, as ``attach(to:)`` does, so an AppKit
            /// app can open the drawer in any of its windows with this call alone. A sheet's window
            /// opens the drawer of the window the sheet is on. In release builds it does nothing.
            ///
            /// - Parameter window: The app's window.
            public func toggle(in window: NSWindow) {
                attach(to: window)
                let scope = Self.scope(of: window)
                attachments.first { $0.presentation.scope == scope }?.presentation.isOpen.toggle()
            }

            /// What identifies `window`'s drawer: the app's window behind it.
            static func scope(of window: NSWindow) -> ObjectIdentifier {
                ObjectIdentifier(appWindow(for: window))
            }

            /// The app's window behind `window`: the window a sheet is on, or the window a drawer
            /// panel or overlay belongs to.
            static func appWindow(for window: NSWindow) -> NSWindow {
                if let panel = window as? DrawerChildPanel, let host = panel.host { return appWindow(for: host) }
                if let chrome = window as? DrawerChromePanel, let host = chrome.host { return appWindow(for: host) }
                if let overlay = window as? DrawerOverlayWindow, let host = overlay.host { return appWindow(for: host) }
                if let parent = window.sheetParent { return appWindow(for: parent) }
                return window
            }
        #elseif os(iOS)
            /// Shows the drawer in `scene`, in a window of its own above the scene's windows, its
            /// sheets and its alerts, with the HUD and the toasts; touches outside the open panel,
            /// the HUD and the toast reach the app's windows.
            ///
            /// `debugDrawer()` calls this for the scene its view is in; call it yourself from a
            /// UIKit app's scene delegate, once the scene has connected. Attaching a scene twice
            /// does nothing. The drawer's open state belongs to the scene: ``isOpen`` and
            /// ``toggle()`` act on the scene in front, and ``toggle(in:)`` on the scene given. It
            /// lists the global plugins and the local plugins of the scene's own views. The drawer
            /// detaches when the scene disconnects. In release builds it does nothing.
            ///
            /// - Parameter scene: The app's window scene.
            public func attach(to scene: UIWindowScene) {
                pruneAttachments()
                guard !attachments.contains(where: { $0.scene === scene }) else { return }
                let presentation = adoptDetachedState()
                presentation.scope = Self.scope(of: scene)
                let window = DrawerSceneWindow(scene: scene, drawer: self, presentation: presentation)
                attachments.append(DrawerAttachment(
                    presentation: presentation,
                    scene: scene,
                    window: window,
                    chrome: DrawerChromeWindow(scene: scene, drawer: self)
                ))
                if presentation.isOpen { window.drawerWillShow() }
                presentationDidChange()
            }

            /// Opens the drawer in `scene` if it is closed there and closes it if it is open,
            /// whichever scene is in front; the other scenes' drawers stay as they are.
            ///
            /// A scene not attached yet is attached first, as ``attach(to:)`` does, so a UIKit app
            /// can open the drawer in any of its scenes with this call alone. In release builds it
            /// does nothing.
            ///
            /// - Parameter scene: The app's window scene.
            public func toggle(in scene: UIWindowScene) {
                attach(to: scene)
                let scope = Self.scope(of: scene)
                attachments.first { $0.presentation.scope == scope }?.presentation.isOpen.toggle()
            }

            /// What identifies `scene`'s drawer.
            static func scope(of scene: UIWindowScene) -> ObjectIdentifier {
                ObjectIdentifier(scene)
            }

            /// Hides and forgets the drawer of a scene that has disconnected.
            private func sceneDidDisconnect(_ scene: UIScene) {
                guard let attachment = attachments.first(where: { $0.scene === scene }) else { return }
                attachment.window.isHidden = true
                attachment.chrome.isHidden = true
                detach(attachment.presentation)
            }
        #endif

        /// A new window's drawer, open if the drawer was opened before any window was attached
        /// (an app that toggles it at launch), which leaves the detached drawer closed.
        private func adoptDetachedState() -> DrawerPresentation {
            let presentation = DrawerPresentation()
            #if os(macOS) || os(iOS)
                observeKeyWindowChanges()
                guard attachments.isEmpty else { return presentation }
                presentation.revealRequest = detachedPresentation.revealRequest
                presentation.isOpen = detachedPresentation.isOpen
                detachedPresentation.revealRequest = nil
                detachedPresentation.isOpen = false
            #endif
            return presentation
        }

        #if os(macOS) || os(iOS)
        /// Keeps ``isOpen`` the key window's as the key window (on iOS, the scene in front)
        /// changes, and on iOS forgets a scene's drawer when the scene disconnects.
        private func observeKeyWindowChanges() {
            guard windowObservers.isEmpty else { return }
            let center = NotificationCenter.default
            #if os(macOS)
                windowObservers.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.presentationDidChange() }
                })
            #elseif os(iOS)
                for name in [UIScene.didActivateNotification, UIWindow.didBecomeKeyNotification] {
                    windowObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                        MainActor.assumeIsolated { self?.presentationDidChange() }
                    })
                }
                let disconnected = UIScene.didDisconnectNotification
                windowObservers.append(center.addObserver(forName: disconnected, object: nil, queue: .main) { [weak self] notification in
                    guard let scene = notification.object as? UIScene else { return }
                    MainActor.assumeIsolated { self?.sceneDidDisconnect(scene) }
                })
            #endif
        }
        #endif

        /// Forgets a window's drawer and the local plugins its views registered, as its window
        /// closes.
        func detach(_ presentation: DrawerPresentation) {
            attachments.removeAll { $0.presentation === presentation }
            if let scope = presentation.scope {
                localRegistrations.removeAll { $0.scope == scope }
            }
            presentationDidChange()
        }

        /// Forgets the drawers whose window or scene has gone.
        private func pruneAttachments() {
            #if os(macOS)
                attachments.removeAll { $0.window == nil }
            #elseif os(iOS)
                attachments.removeAll { $0.scene == nil }
            #endif
        }

        /// Every drawer: each window's, then the detached one.
        var presentations: [DrawerPresentation] {
            attachments.map(\.presentation) + [detachedPresentation]
        }

        /// The drawer of the key window (the main window, or the frontmost while the app isn't
        /// active; on iOS, of the scene with the key window, or else the foreground-active one), or
        /// the last window's attached when none is, or the detached one when none is attached.
        var keyPresentation: DrawerPresentation {
            #if os(macOS)
                let live = attachments.filter { $0.window != nil }
                let app = NSApplication.shared
                // While the app isn't active it has no key or main window; its frontmost window
                // is the one the user comes back to.
                let front = ([app.keyWindow, app.mainWindow].compactMap(\.self) + app.orderedWindows).map(Self.scope(of:))
            #elseif os(iOS)
                let live = attachments.filter { $0.scene != nil }
                let scenes = live.compactMap(\.scene)
                // Two scenes side by side are both foreground-active; the one holding the app's key
                // window is the one the user last touched.
                let keyScenes = scenes.filter { $0.windows.contains(where: \.isKeyWindow) }
                let activeScenes = scenes.filter { $0.activationState == .foregroundActive }
                let front = (keyScenes + activeScenes).map(Self.scope(of:))
            #else
                let live = attachments
                let front: [ObjectIdentifier] = []
            #endif
            return Self.frontPresentation(of: live.map(\.presentation), front: front) ?? detachedPresentation
        }

        /// The drawer ``toggle()`` acts on: the first window in `front` that has one, or else the
        /// last attached. The Mac and iOS share it, each naming its windows or scenes in front.
        ///
        /// - Parameters:
        ///   - presentations: The attached windows' drawers, in the order they were attached.
        ///   - front: The windows (scenes) the user is working in, most recent first.
        /// - Returns: The drawer to act on, or `nil` when none is attached.
        static func frontPresentation(of presentations: [DrawerPresentation], front: [ObjectIdentifier]) -> DrawerPresentation? {
            let inFront = front.lazy.compactMap { scope in presentations.first { $0.scope == scope } }.first
            return inFront ?? presentations.last
        }

        /// Brings ``isOpen`` up to date with the key window's drawer, and tells the views that
        /// read the drawer that one window's drawer changed.
        func presentationDidChange() {
            isSyncingOpenState = true
            defer { isSyncingOpenState = false }
            let keyIsOpen = keyPresentation.isOpen
            if isOpen != keyIsOpen {
                isOpen = keyIsOpen
            } else {
                objectWillChange.send()
            }
        }
    }

    #if os(macOS)
        /// The app's key window, or, while the drawer's panel is key (its search field has focus),
        /// the window that panel belongs to: the window a plugin captures, inspects or changes.
        @MainActor package var debugDrawerAppKeyWindow: NSWindow? {
            NSApplication.shared.keyWindow.map { window in
                (window as? DrawerChildPanel)?.host ?? window
            }
        }
    #elseif os(iOS)
        /// The key window of the scene in front, or, while the drawer's window is key (its search
        /// field has focus), the scene's frontmost window of the app's own: the window a plugin
        /// captures, inspects or changes.
        @MainActor package var debugDrawerAppKeyWindow: UIWindow? {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) else { return nil }
            let appWindows = scene.windows.filter { !isDebugDrawerWindow($0) }
            return appWindows.first(where: \.isKeyWindow)
                ?? appWindows.filter { !$0.isHidden }.max { $0.windowLevel < $1.windowLevel }
        }

        /// Whether `window` is the drawer's own (its window, its HUD's or an overlay), which a
        /// plugin that draws or inspects the app's windows leaves out.
        @MainActor package func isDebugDrawerWindow(_ window: UIWindow) -> Bool {
            window is DrawerSceneWindow || window is DrawerChromeWindow || window is DrawerOverlayWindow
        }
    #endif
#else
    #if os(macOS)
        import AppKit
    #elseif os(iOS)
        import UIKit
    #endif

    // The release stand-ins: the same signatures, so a UIKit or AppKit host compiles unchanged.
    public extension DebugDrawer {
        #if os(macOS)
            /// Does nothing: release builds have no drawer.
            ///
            /// - Parameter window: Ignored.
            func attach(to window: NSWindow) {}

            /// Does nothing: release builds have no drawer to open.
            ///
            /// - Parameter window: Ignored.
            func toggle(in window: NSWindow) {}
        #elseif os(iOS)
            /// Does nothing: release builds have no drawer.
            ///
            /// - Parameter scene: Ignored.
            func attach(to scene: UIWindowScene) {}

            /// Does nothing: release builds have no drawer to open.
            ///
            /// - Parameter scene: Ignored.
            func toggle(in scene: UIWindowScene) {}
        #endif
    }
#endif
