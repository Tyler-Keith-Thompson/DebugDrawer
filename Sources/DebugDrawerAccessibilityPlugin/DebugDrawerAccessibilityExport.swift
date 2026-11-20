// The Accessibility module holds what a release build needs of accessibility overrides: the
// receiver's capability that lets a sidecar override Dynamic Type, Increase Contrast and Reduce
// Motion during its session, and the modifier the host's root view applies them with, real in
// every build and with no drawer. The plugin, the drawer's half, depends on it and re-exports it,
// so `import DebugDrawerAccessibilityPlugin` sees them too. Rejected: the capability in the
// receiver (the receiver must stay free of SwiftUI, and every production app would link it), and
// the plugin linked into release builds (it depends on the drawer).
@_exported import DebugDrawerAccessibility
