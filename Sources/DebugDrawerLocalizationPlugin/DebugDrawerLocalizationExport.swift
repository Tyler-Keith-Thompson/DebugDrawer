// The Localization module holds what a release build needs of localization: the modes, the
// pseudo-localization they draw strings with, and the receiver's capability that lets a sidecar
// set a mode for the strings the host reads through `LocalizationReview`, real in every build and
// with no drawer. The plugin, the drawer's half, depends on it and re-exports it, so
// `import DebugDrawerLocalizationPlugin` keeps seeing `Localization` and its modes where they
// were. Rejected: the capability in the receiver (the receiver would hold a plugin's vocabulary,
// and every production app would link it), and the plugin linked into release builds (it depends
// on the drawer, and its modes replace `Bundle`'s lookups, interception the charter keeps out of
// release builds).
@_exported import DebugDrawerLocalization
