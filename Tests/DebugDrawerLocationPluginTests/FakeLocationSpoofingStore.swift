@testable import DebugDrawerLocationPlugin
import os

/// The switch and coordinate kept in memory, so no test writes the drawer's defaults.
final class FakeLocationSpoofingStore: LocationSpoofingStore {
    private struct Kept {
        var isEnabled = false
        var coordinate: LocationCoordinate?
    }

    // A lock, as the simulator reads the store from whatever thread asks it.
    private let kept: OSAllocatedUnfairLock<Kept>

    /// - Parameters:
    ///   - isEnabled: The switch kept from a "previous launch".
    ///   - coordinate: The coordinate kept, as stored.
    init(isEnabled: Bool = false, coordinate: LocationCoordinate? = nil) {
        kept = OSAllocatedUnfairLock(initialState: Kept(isEnabled: isEnabled, coordinate: coordinate))
    }

    var isEnabled: Bool {
        get { kept.withLock { $0.isEnabled } }
        set { kept.withLock { $0.isEnabled = newValue } }
    }

    var coordinate: LocationCoordinate? {
        get { kept.withLock { $0.coordinate } }
        set { kept.withLock { $0.coordinate = newValue } }
    }
}
