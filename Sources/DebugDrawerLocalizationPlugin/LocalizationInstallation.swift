#if DEBUG
    import DebugDrawer

    /// What `Localization.install(mode:)` does in debug builds, and what the plugin's
    /// ``LocalizationPlugin/install(in:)`` and ``LocalizationPlugin/uninstall(from:)`` start and
    /// stop: the interception of `Bundle`'s lookups, shared by every drawer the plugin is in.
    @MainActor
    enum LocalizationInstallation {
        /// The drawers the plugin is installed in, by identity; lookups are intercepted while
        /// there is one.
        private static var drawers: Set<ObjectIdentifier> = []

        /// Registers the plugin over the app's tables in `mode`, replacing one installed before;
        /// its install starts intercepting the app's lookups.
        ///
        /// - Returns: The plugin's model.
        @discardableResult
        static func install(
            mode: Localization.Mode,
            source: any LocalizationTableSource = BundleTableSource(appBundles: .main),
            state: LocalizationState = .shared
        ) -> LocalizationModel {
            // The plugin installed before is removed first: its uninstall puts the mode back and
            // stops intercepting, then the new model starts from this mode.
            DebugDrawer.shared.unregisterGlobal(id: LocalizationPlugin.pluginID)
            state.mode = mode
            let model = LocalizationModel(source: source, state: state, nextLaunchDefaults: .standard) {
                LocalizationRedraw.shared.modeChanged()
            }
            DebugDrawer.shared.registerGlobal(LocalizationPlugin(model: model))
            return model
        }

        /// Intercepts the app's lookups while `drawer` holds the plugin, and reads `model`'s
        /// tables; the first drawer replaces the lookups.
        static func start(_ model: LocalizationModel, in drawer: DebugDrawer) {
            let isFirst = drawers.isEmpty
            drawers.insert(ObjectIdentifier(drawer))
            Task { await model.refresh() }
            if isFirst {
                LocalizationInterception.install()
            }
        }

        /// Stops what ``start(_:in:)`` began for `drawer`; the last drawer puts the lookups back,
        /// sets `model`'s mode back to standard and drops what it read and recorded. A drawer
        /// that isn't intercepting changes nothing.
        static func stop(_ model: LocalizationModel, from drawer: DebugDrawer) {
            guard drawers.remove(ObjectIdentifier(drawer)) != nil, drawers.isEmpty else { return }
            LocalizationInterception.uninstall()
            model.unload()
            BundleTableKeys.shared.removeAll()
        }
    }
#endif
