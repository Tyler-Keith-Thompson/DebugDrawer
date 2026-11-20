// The App State Reset module holds what a release build needs: the categories, how each is read and
// deleted, and the receiver capability through which a sidecar asks for a reset, real in every
// build and with no drawer. The plugin, the drawer's half, depends on it and re-exports it, so
// `import DebugDrawerAppStateResetPlugin` keeps seeing `AppStateReset`, and the drawer and a
// sidecar clear the same state through the same code. Rejected: the capability in the receiver
// (every production app would link the reset, WebKit's cookie store among it), and the plugin
// linked into release builds (it depends on the drawer, which a production app doesn't link).
@_exported import DebugDrawerAppStateReset
