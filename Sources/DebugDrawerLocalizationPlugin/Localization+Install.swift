import DebugDrawerLocalization

public extension Localization {
    /// Adds the Localization plugin and starts intercepting the app's string lookups: in debug
    /// builds only; in release it does nothing.
    ///
    /// The plugin reads every `.strings` and `.stringsdict` table of the app's bundles (the main
    /// bundle and the bundles inside it) and records, from then on, the keys the app looks up and
    /// gets no translation for. Call it once at startup, before the first string is looked up,
    /// so the lookups at launch are recorded too. Calling it again replaces the plugin and sets
    /// the mode. Removing the plugin from the drawer puts the lookups back.
    ///
    /// - Parameter mode: What the app's strings show until the drawer changes it, such as
    ///   ``Mode/pseudoLocalized`` for a launch argument of the app's own.
    @MainActor
    static func install(mode: Mode = .standard) {
        #if DEBUG
            LocalizationInstallation.install(mode: mode)
        #endif
    }
}
