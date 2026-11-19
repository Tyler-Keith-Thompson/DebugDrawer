#if DEBUG
    #if os(macOS)
        import AppKit
    #elseif os(iOS) || os(visionOS)
        import UIKit
    #endif

    // Local plugins an AppKit or UIKit host registers for one window, which has no SwiftUI view for
    // `debugLocalPlugin(_:)` to find it from. Each registration is the scoped one that modifier
    // makes; the window's close (the scene's disconnect) removes them, as it does its views'.
    extension DebugDrawer {
        #if os(macOS)
            /// Registers a plugin listed only in `window`'s drawer, replacing a local plugin with the
            /// same ID registered for that window.
            ///
            /// The AppKit counterpart of `debugLocalPlugin(_:)`: the other windows' drawers don't
            /// list the plugin. A sheet's window registers for the window the sheet is on. The window
            /// needn't be attached yet; its drawer lists the plugin once ``attach(to:)`` or
            /// ``toggle(in:)`` attaches it. The registration ends when the window closes, or when
            /// ``unregisterLocal(id:token:)`` is passed the token. In release builds it does nothing.
            ///
            /// - Parameters:
            ///   - plugin: The plugin to add.
            ///   - window: The window whose drawer lists it.
            /// - Returns: The token that owns the registration; pass it to
            ///   ``unregisterLocal(id:token:)``. Only the latest registration's token removes the plugin.
            @discardableResult
            public func registerLocal<P: DebugDrawerPlugin>(_ plugin: P, in window: NSWindow) -> UUID {
                let host = Self.appWindow(for: window)
                return registerLocal(plugin, scope: Self.scope(of: host), until: NSWindow.willCloseNotification, from: host)
            }
        #elseif os(iOS) || os(visionOS)
            /// Registers a plugin listed only in `scene`'s drawer, replacing a local plugin with the
            /// same ID registered for that scene.
            ///
            /// The UIKit counterpart of `debugLocalPlugin(_:)`: the other scenes' drawers don't list
            /// the plugin. The scene needn't be attached yet; on iOS its drawer lists the plugin once
            /// `attach(to:)` or `toggle(in:)` attaches it. visionOS has one drawer, which lists every
            /// local plugin. The registration ends when the scene disconnects, or when
            /// ``unregisterLocal(id:token:)`` is passed the token. In release builds it does nothing.
            ///
            /// - Parameters:
            ///   - plugin: The plugin to add.
            ///   - scene: The window scene whose drawer lists it.
            /// - Returns: The token that owns the registration; pass it to
            ///   ``unregisterLocal(id:token:)``. Only the latest registration's token removes the plugin.
            @discardableResult
            public func registerLocal<P: DebugDrawerPlugin>(_ plugin: P, in scene: UIWindowScene) -> UUID {
                #if os(iOS)
                    let scope = Self.scope(of: scene)
                #else
                    // The identifier iOS's scope(of:) gives: visionOS attaches no scene, so it only
                    // ties the registration to the scene's lifetime.
                    let scope = ObjectIdentifier(scene)
                #endif
                return registerLocal(plugin, scope: scope, until: UIScene.didDisconnectNotification, from: scene)
            }
        #endif

        #if os(macOS) || os(iOS) || os(visionOS)
            /// Registers `plugin` for the drawer of the window `scope` identifies until `window`
            /// posts `name` (it closes, or its scene disconnects), which removes every local plugin
            /// registered for that window; one observer per window, kept until then.
            ///
            /// - Returns: The token that owns the registration.
            @discardableResult
            func registerLocal(
                _ plugin: some DebugDrawerPlugin,
                scope: ObjectIdentifier,
                until name: Notification.Name,
                from window: AnyObject
            ) -> UUID {
                if localScopeObservers[scope] == nil {
                    let center = NotificationCenter.default
                    localScopeObservers[scope] = center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                        MainActor.assumeIsolated { self?.forgetLocalPlugins(of: scope) }
                    }
                }
                return registerLocal(plugin, scope: scope)
            }

            /// Removes the local plugins registered for the window `scope` identifies, and stops
            /// watching that window close.
            private func forgetLocalPlugins(of scope: ObjectIdentifier) {
                if let observer = localScopeObservers.removeValue(forKey: scope) {
                    NotificationCenter.default.removeObserver(observer)
                }
                guard localRegistrations.contains(where: { $0.scope == scope }) else { return }
                localRegistrations.removeAll { $0.scope == scope }
            }
        #endif
    }
#else
    #if os(macOS)
        import AppKit
    #elseif os(iOS) || os(visionOS)
        import UIKit
    #endif

    // The release stand-ins: the same signatures, so a UIKit or AppKit host compiles unchanged.
    public extension DebugDrawer {
        #if os(macOS)
            /// Drops the plugin: release builds have no drawer.
            ///
            /// - Parameters:
            ///   - plugin: Ignored.
            ///   - window: Ignored.
            /// - Returns: A token that unregisters nothing.
            @discardableResult
            func registerLocal<P: DebugDrawerPlugin>(_ plugin: P, in window: NSWindow) -> UUID {
                UUID()
            }
        #elseif os(iOS) || os(visionOS)
            /// Drops the plugin: release builds have no drawer.
            ///
            /// - Parameters:
            ///   - plugin: Ignored.
            ///   - scene: Ignored.
            /// - Returns: A token that unregisters nothing.
            @discardableResult
            func registerLocal<P: DebugDrawerPlugin>(_ plugin: P, in scene: UIWindowScene) -> UUID {
                UUID()
            }
        #endif
    }
#endif
