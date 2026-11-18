#if DEBUG
    import Foundation

    /// One local plugin's registration: the plugin, the token that owns it, and the window whose
    /// views registered it.
    struct DrawerLocalRegistration {
        /// What ``DebugDrawer/registerLocal(_:)`` returned; only it removes the registration.
        let token: UUID
        /// The plugin's latest value, which ``plugin`` reads its views from.
        let content: LocalPluginContent
        /// The plugin as the drawer lists it, following ``content``.
        let plugin: AnyDebugDrawerPlugin
        /// The window (on iOS, the scene) whose views registered the plugin, which alone lists it;
        /// `nil` lists it in every window's drawer.
        ///
        /// An identifier rather than a weak reference, so a registration from a window that has
        /// gone can't be mistaken for one from no window; the drawer forgets a window's
        /// registrations as the window detaches, before its identifier can be reused.
        var scope: ObjectIdentifier?

        /// The registration `token` owns of `plugin`, for the drawer of the window `scope`
        /// identifies.
        @MainActor init(token: UUID, plugin: AnyDebugDrawerPlugin, scope: ObjectIdentifier?) {
            self.token = token
            content = LocalPluginContent(plugin)
            self.plugin = AnyDebugDrawerPlugin(following: content)
            self.scope = scope
        }

        /// Whether the drawer of the window `scope` identifies lists this plugin: every drawer lists
        /// a plugin registered from no window, and the detached drawer (`scope` is `nil`) lists
        /// every plugin.
        func isListed(in scope: ObjectIdentifier?) -> Bool {
            scope == nil || self.scope == nil || self.scope == scope
        }
    }

    extension [DrawerLocalRegistration] {
        /// The registrations with `registration` in place: it replaces the registration with the
        /// same token (one moving to another window), then one of the same plugin in the same
        /// window, keeping its place in the list, or it goes last.
        func placing(_ registration: DrawerLocalRegistration) -> [DrawerLocalRegistration] {
            var registrations = filter { $0.token != registration.token }
            let sameSlot = registrations.firstIndex { $0.plugin.id == registration.plugin.id && $0.scope == registration.scope }
            if let sameSlot {
                registrations[sameSlot] = registration
            } else {
                registrations.append(registration)
            }
            return registrations
        }

        /// The plugins the drawer of the window `scope` identifies lists, in the order they were
        /// registered, each ID once.
        func plugins(listedIn scope: ObjectIdentifier?) -> [AnyDebugDrawerPlugin] {
            var seen = Set<String>()
            return filter { $0.isListed(in: scope) && seen.insert($0.plugin.id).inserted }.map(\.plugin)
        }
    }
#endif
