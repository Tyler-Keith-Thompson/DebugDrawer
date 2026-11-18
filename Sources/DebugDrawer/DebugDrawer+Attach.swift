#if DEBUG
    #if os(macOS)
        import AppKit
    #elseif os(iOS)
        import UIKit
    #endif

    /// A window's drawer: its state and, on the Mac and iOS, the window it is drawn in.
    @MainActor
    struct DrawerAttachment {
        let presentation: DrawerPresentation
        #if os(macOS)
            /// The window the drawer is attached to.
            weak var window: NSWindow?
            let panel: DrawerChildPanel
        #elseif os(iOS)
            /// The scene the drawer is attached to.
            weak var scene: UIWindowScene?
            let window: DrawerSceneWindow
        #endif
    }

    extension DebugDrawer {
        #if os(macOS)
            /// Shows the drawer over `window`, in a panel of its own along the window's trailing
            /// edge, above its sheets and alerts.
            ///
            /// `debugDrawer()` calls this for the window its view is in; call it yourself from an
            /// AppKit app, once the window exists. Attaching a window twice does nothing; a sheet
            /// attaches the window it is on. The drawer's open state belongs to the window:
            /// ``isOpen`` and ``toggle()`` act on the key window's. The drawer detaches when the
            /// window closes. In release builds it does nothing.
            ///
            /// - Parameter window: The app's window.
            public func attach(to window: NSWindow) {
                let host = Self.appWindow(for: window)
                pruneAttachments()
                guard !attachments.contains(where: { $0.window === host }) else { return }
                let presentation = adoptDetachedState()
                let panel = DrawerChildPanel(host: host, drawer: self, presentation: presentation)
                attachments.append(DrawerAttachment(presentation: presentation, window: host, panel: panel))
                if presentation.isOpen { panel.drawerWillShow() }
                presentationDidChange()
            }

            /// The app's window behind `window`: the window a sheet is on, or the window a drawer
            /// panel belongs to.
            static func appWindow(for window: NSWindow) -> NSWindow {
                if let panel = window as? DrawerChildPanel, let host = panel.host { return appWindow(for: host) }
                if let parent = window.sheetParent { return appWindow(for: parent) }
                return window
            }
        #elseif os(iOS)
            /// Shows the drawer in `scene`, in a window of its own above the scene's windows, its
            /// sheets and its alerts; touches outside the open panel reach the app's windows.
            ///
            /// `debugDrawer()` calls this for the scene its view is in; call it yourself from a
            /// UIKit app's scene delegate, once the scene has connected. Attaching a scene twice
            /// does nothing. The drawer's open state belongs to the scene: ``isOpen`` and
            /// ``toggle()`` act on the scene in front. The drawer detaches when the scene
            /// disconnects. In release builds it does nothing.
            ///
            /// - Parameter scene: The app's window scene.
            public func attach(to scene: UIWindowScene) {
                pruneAttachments()
                guard !attachments.contains(where: { $0.scene === scene }) else { return }
                let presentation = adoptDetachedState()
                let window = DrawerSceneWindow(scene: scene, drawer: self, presentation: presentation)
                attachments.append(DrawerAttachment(presentation: presentation, scene: scene, window: window))
                if presentation.isOpen { window.drawerWillShow() }
                presentationDidChange()
            }

            /// Hides and forgets the drawer of a scene that has disconnected.
            private func sceneDidDisconnect(_ scene: UIScene) {
                guard let attachment = attachments.first(where: { $0.scene === scene }) else { return }
                attachment.window.isHidden = true
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
        /// Keeps ``isOpen`` the key window's as the key window changes, and on iOS forgets a
        /// scene's drawer when the scene disconnects.
        private func observeKeyWindowChanges() {
            guard windowObservers.isEmpty else { return }
            let center = NotificationCenter.default
            #if os(macOS)
                windowObservers.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.presentationDidChange() }
                })
            #elseif os(iOS)
                windowObservers.append(center.addObserver(forName: UIScene.didActivateNotification, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.presentationDidChange() }
                })
                let disconnected = UIScene.didDisconnectNotification
                windowObservers.append(center.addObserver(forName: disconnected, object: nil, queue: .main) { [weak self] notification in
                    guard let scene = notification.object as? UIScene else { return }
                    MainActor.assumeIsolated { self?.sceneDidDisconnect(scene) }
                })
            #endif
        }
        #endif

        /// Forgets a window's drawer, as its window closes.
        func detach(_ presentation: DrawerPresentation) {
            attachments.removeAll { $0.presentation === presentation }
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

        /// The drawer of the key window (on iOS, of the scene in front), or the last window's
        /// attached when none is key, or the detached one when none is attached.
        var keyPresentation: DrawerPresentation {
            let live = attachments.filter { attachment in
                #if os(macOS)
                    attachment.window != nil
                #elseif os(iOS)
                    attachment.scene != nil
                #else
                    true
                #endif
            }
            #if os(macOS)
                let app = NSApplication.shared
                for candidate in [app.keyWindow, app.mainWindow].compactMap(\.self) {
                    let window = Self.appWindow(for: candidate)
                    if let attachment = live.first(where: { $0.window === window }) { return attachment.presentation }
                }
            #elseif os(iOS)
                if let attachment = live.first(where: { $0.scene?.activationState == .foregroundActive }) {
                    return attachment.presentation
                }
            #endif
            return live.last?.presentation ?? detachedPresentation
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
            let appWindows = scene.windows.filter { !($0 is DrawerSceneWindow) }
            return appWindows.first(where: \.isKeyWindow)
                ?? appWindows.filter { !$0.isHidden }.max { $0.windowLevel < $1.windowLevel }
        }

        /// Whether `window` is the drawer's own, which a plugin that draws the app's windows leaves
        /// out.
        @MainActor package func isDebugDrawerWindow(_ window: UIWindow) -> Bool {
            window is DrawerSceneWindow
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
        #elseif os(iOS)
            /// Does nothing: release builds have no drawer.
            ///
            /// - Parameter scene: Ignored.
            func attach(to scene: UIWindowScene) {}
        #endif
    }
#endif
