// The MetricKit module holds what a release build needs of MetricKit: the payload kinds, the
// MXMetricManager subscriber, and the receiver's capability that keeps the payloads, crash
// diagnostics among them, for a sidecar, real in every build and with no drawer. The plugin, the
// drawer's half, depends on it and re-exports it, so `import DebugDrawerMetricKitPlugin` keeps
// seeing `MetricKitPayloadKind` where it was, and subscribes through the same source. Rejected: the
// capability in the receiver (the receiver would hold a plugin's vocabulary, and every production
// app would link it), and the plugin linked into release builds (it depends on the drawer, which
// a production app doesn't link).
@_exported import DebugDrawerMetricKit
