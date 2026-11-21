// The Location module holds what a release build needs of location spoofing: the coordinate the
// plugin and the receiver capability carry, and the capability that lets a sidecar spoof the
// locations the host reads through `LocationSpoofing`, real in every build and with no drawer. The
// plugin, the drawer's half, depends on it and re-exports it, so `import DebugDrawerLocationPlugin`
// sees `LocationCoordinate` and the capability too. Rejected: the capability in the receiver (the
// receiver would hold a plugin's vocabulary, and every production app would link it), and the
// plugin linked into release builds (it depends on the drawer, and its spoofing exchanges
// `CLLocationManager`'s methods, interception the charter keeps out of release builds).
@_exported import DebugDrawerLocation
