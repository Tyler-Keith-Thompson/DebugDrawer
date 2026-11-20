// The Hang Detector module holds what a release build needs of hang detection: the monitor (a main
// run loop observer and a watcher thread that samples the main thread's stack) and the receiver's
// capability that records stalls and the host's signpost intervals for a sidecar, real in every
// build and with no drawer. The plugin, the drawer's half, depends on it and re-exports it, so
// `import DebugDrawerHangDetectorPlugin` keeps seeing everything it did and runs the same monitor.
// Rejected: the capability in the receiver (the receiver would hold a plugin's monitor, and every
// production app would link it), and the plugin linked into release builds (it depends on the
// drawer, which a production app doesn't link).
@_exported import DebugDrawerHangDetector
