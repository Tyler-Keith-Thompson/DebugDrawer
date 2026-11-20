// The Network module holds what a release build needs of the Network plugin: the mock rules and
// conditioning profiles, the matcher and the conditioned delivery that answer requests with them,
// and the receiver's network-mocking capability, real in every build and with no drawer. The
// plugin, the drawer's half, depends on it and re-exports it, so `import DebugDrawerNetworkPlugin`
// keeps seeing `NetworkMockRule` and `NetworkConditionProfile` where they were, and the drawer's
// interception answers with the same code. Rejected: the capability in the receiver (the receiver
// would hold a plugin's vocabulary, and every production app would link it), and the plugin linked
// into release builds (it depends on the drawer, and its interception is global).
@_exported import DebugDrawerNetwork
