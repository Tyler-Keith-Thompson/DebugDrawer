// The App Info module holds what a release build needs: the build's metadata, read from the
// Info.plist as App Info reads it, and the receiver capability that shows a sidecar the app's state,
// real in every build and with no drawer. The plugin, the drawer's half, depends on it and
// re-exports it, so `import DebugDrawerAppInfoPlugin` keeps seeing `AppInfoBuildMetadata`.
// Rejected: the app state capability in the receiver beside environments and flags (it would read
// the build's metadata from the Info.plist a second time, apart from App Info, and the two would
// drift), and the plugin linked into release builds (it depends on the drawer).
@_exported import DebugDrawerAppInfo
