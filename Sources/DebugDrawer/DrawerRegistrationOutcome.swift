#if DEBUG
    /// What registering a global plugin does, given the plugins already registered.
    enum DrawerRegistrationOutcome {
        /// No plugin has its ID: it is added.
        case added
        /// A plugin of the same type has its ID, as when an install runs twice: nothing changes.
        case alreadyRegistered
        /// A plugin of another type has its ID: nothing changes, and the drawer logs an error,
        /// since one of the two needs an ID of its own.
        case collision(AnyDebugDrawerPlugin)

        /// What registering `plugin` among `registered` does.
        ///
        /// - Complexity: O(*n*) in the number of registered plugins.
        init(of plugin: AnyDebugDrawerPlugin, among registered: [AnyDebugDrawerPlugin]) {
            guard let existing = registered.first(where: { $0.id == plugin.id }) else {
                self = .added
                return
            }
            self = existing.typeName == plugin.typeName ? .alreadyRegistered : .collision(existing)
        }
    }
#endif
