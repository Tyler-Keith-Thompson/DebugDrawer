// The Tweaks module holds what a release build needs of the tweaks: the declarations, their
// storage and typed accessors, and the receiver's tweaks capability, real in every build and with
// no drawer. The plugin, the drawer's half, depends on it and re-exports it, so
// `import DebugDrawerTweaksPlugin` keeps seeing `Tweak`, `TweakStorage` and the rest where they
// were. Rejected: the capability in the receiver (the receiver would hold a plugin's vocabulary,
// and every production app would link it), and the plugin linked into release builds (it depends
// on the drawer, which a production app doesn't link).
@_exported import DebugDrawerTweaks
