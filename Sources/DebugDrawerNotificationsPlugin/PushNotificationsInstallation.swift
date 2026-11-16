#if DEBUG
    import DebugDrawer

    /// What `PushNotifications`' calls do in debug builds.
    @MainActor
    enum PushNotificationsInstallation {
        /// What the app reported last, kept so a token that arrives before `install` shows once it
        /// runs.
        private static var registration = RemoteRegistration.notRegistered
        /// The model of the latest install, which reports go to.
        private static var model: NotificationsModel?

        /// Registers the plugin over `client`, read again on each change `changes` reports, and
        /// reads it once now.
        ///
        /// - Returns: The plugin's model.
        @discardableResult
        static func install(
            client: any NotificationCenterClient = SystemNotificationCenterClient(),
            changes: any NotificationChangeSource = AppActivationChangeSource()
        ) -> NotificationsModel {
            let model = NotificationsModel(registration: registration, client: client, changes: changes)
            Self.model = model
            let plugin = NotificationsPlugin(model: model)
            DebugDrawer.shared.unregisterGlobal(id: plugin.id)
            DebugDrawer.shared.registerGlobal(plugin)
            Task { await model.refresh() }
            return model
        }

        /// Keeps what the app reported and shows it.
        static func update(_ registration: RemoteRegistration) {
            Self.registration = registration
            model?.update(registration)
        }
    }
#endif
