import CoreLocation
@testable import DebugDrawerLocationPlugin
import os

/// Core Location's behavior as a record of the calls the simulator let through, so no test
/// starts the Mac's location service.
final class RecordingLocationService: LocationService {
    /// A call the simulator made, and the manager it was for.
    enum Call: Equatable {
        case startUpdatingLocation(ObjectIdentifier)
        case stopUpdatingLocation(ObjectIdentifier)
        case requestLocation(ObjectIdentifier)
    }

    private let recorded = OSAllocatedUnfairLock<[Call]>(initialState: [])

    /// Every call so far, in order.
    var calls: [Call] { recorded.withLock { $0 } }

    func startUpdatingLocation(_ manager: CLLocationManager) {
        record(.startUpdatingLocation(ObjectIdentifier(manager)))
    }

    func stopUpdatingLocation(_ manager: CLLocationManager) {
        record(.stopUpdatingLocation(ObjectIdentifier(manager)))
    }

    func requestLocation(_ manager: CLLocationManager) {
        record(.requestLocation(ObjectIdentifier(manager)))
    }

    private func record(_ call: Call) {
        recorded.withLock { $0.append(call) }
    }

    func location(of manager: CLLocationManager) -> CLLocation? {
        nil
    }
}
