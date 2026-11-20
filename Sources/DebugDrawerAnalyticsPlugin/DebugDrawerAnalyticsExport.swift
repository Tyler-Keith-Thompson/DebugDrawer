// The Analytics module holds what a release build needs of analytics: the sink
// (`AnalyticsEvents.record`), its values, and the receiver's capability that mirrors events to a
// sidecar with their redaction, real in every build and with no drawer. The plugin, the drawer's
// half, depends on it and re-exports it, so `import DebugDrawerAnalyticsPlugin` keeps seeing
// `AnalyticsEvents` and `AnalyticsValue` where they were. Rejected: the capability in the receiver
// (the receiver would hold a plugin's vocabulary, and every production app would link it), and
// the plugin linked into release builds (it depends on the drawer, which a production app doesn't
// link).
@_exported import DebugDrawerAnalytics
