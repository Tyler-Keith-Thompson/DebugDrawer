@testable import DebugDrawerLocationPlugin

/// Records the drawers the swaps were asked for, and swaps nothing.
@MainActor
final class FakeLocationInterception: LocationInterception {
    /// The drawers the methods were to be swapped for, in order.
    private(set) var installed: [ObjectIdentifier] = []
    /// The drawers they were to be put back for, in order.
    private(set) var uninstalled: [ObjectIdentifier] = []

    func install(for drawer: ObjectIdentifier) {
        installed.append(drawer)
    }

    func uninstall(for drawer: ObjectIdentifier) {
        uninstalled.append(drawer)
    }
}
