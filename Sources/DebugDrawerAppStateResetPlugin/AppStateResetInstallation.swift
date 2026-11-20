#if DEBUG
    import DebugDrawer
    import DebugDrawerAppStateReset
    import Foundation

    /// What `AppStateReset.install(appGroups:directories:cleanup:)` does in debug builds.
    @MainActor
    enum AppStateResetInstallation {
        /// Registers the plugin over the running app's state, replacing one installed before. The
        /// state is read when the plugin is first shown, not here, so launch costs nothing.
        ///
        /// - Returns: The plugin's model.
        @discardableResult
        static func install(appGroups: [String], directories: [URL], cleanup: AppStateReset.Cleanup?) -> AppStateResetModel {
            let bundleID = Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName
            var groups = AppGroupEntitlements.identifiers()
            groups += appGroups.filter { !groups.contains($0) }
            var appState = AppState(
                domains: [bundleID] + groups,
                preferences: _PreferenceStore(appDomain: bundleID),
                keychain: _Keychain(),
                container: .current(appGroups: groups, directories: directories, appFolderName: bundleID),
                cookies: _CookieStore(),
                responseCache: URLCache.shared,
                cleanup: cleanup,
                debugDrawerDomain: UserDefaults.debugDrawerSuiteName
            )
            appState.container.ownWork = DrawerFileWork()
            let model = AppStateResetModel(appState: appState, process: _AppProcess())
            let plugin = AppStateResetPlugin(model: model)
            DebugDrawer.shared.unregisterGlobal(id: plugin.id)
            DebugDrawer.shared.registerGlobal(plugin)
            return model
        }
    }

    /// Marks the container's walks and deletions as the drawer's own work, which Disk I/O leaves
    /// out.
    struct DrawerFileWork: FileWorkScope {
        func perform<Result>(_ body: () -> Result) -> Result {
            DebugDrawerActivity.$isDrawerWork.withValue(true, operation: body)
        }
    }
#endif
