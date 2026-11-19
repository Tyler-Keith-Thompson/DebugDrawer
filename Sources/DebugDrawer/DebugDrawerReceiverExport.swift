// The receiver's module holds what a release build's receiver shares with the drawer: the plugin
// model protocol, the sidecar's sessions with their scopes and audit log, and the store's wire
// format. The drawer depends on it rather than the other way round, so the receiver links into a
// production app with none of the drawer, and re-exports it, so `import DebugDrawer` keeps seeing
// `DebugDrawerPluginModel`, `DebugDrawerSessions` and the rest where they were. Rejected: a third
// module both depend on (a shared target the charter's N4 forbids, and the receiver would no
// longer stand alone), and copying the wire format into the receiver (two implementations of one
// protocol drift).
@_exported import DebugDrawerReceiver
