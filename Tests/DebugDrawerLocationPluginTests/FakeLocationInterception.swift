@testable import DebugDrawerLocationPlugin

/// Counts the swaps asked for, and swaps nothing.
@MainActor
final class FakeLocationInterception: LocationInterception {
    /// How many times the methods were to be swapped.
    private(set) var installs = 0
    /// How many times they were to be put back.
    private(set) var uninstalls = 0

    func install() {
        installs += 1
    }

    func uninstall() {
        uninstalls += 1
    }
}
