import CoreLocation
@testable import DebugDrawerLocationPlugin

/// What the app's managers would be given, kept in memory, with a record of every change asked
/// of it in order, so no test swaps a method or starts Core Location.
@MainActor
final class FakeLocationOverride: LocationOverride {
    /// A change the model or the route player asked for.
    enum Call: Equatable {
        case setEnabled(Bool)
        case setCoordinate(LocationCoordinate?)
        case deliverRoute(LocationCoordinate)
        case endRoute
    }

    /// Every change so far, in order.
    private(set) var calls: [Call] = []
    private var route: CLLocation?

    var isEnabled: Bool {
        didSet { calls.append(.setEnabled(isEnabled)) }
    }

    var coordinate: CLLocationCoordinate2D? {
        didSet { calls.append(.setCoordinate(coordinate.map { LocationCoordinate(latitude: $0.latitude, longitude: $0.longitude) })) }
    }

    var simulatedLocation: CLLocation? {
        guard isEnabled else { return nil }
        return route ?? coordinate.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
    }

    /// - Parameters:
    ///   - isEnabled: The switch as kept.
    ///   - coordinate: The coordinate as kept.
    init(isEnabled: Bool = false, coordinate: CLLocationCoordinate2D? = nil) {
        self.isEnabled = isEnabled
        self.coordinate = coordinate
    }

    func deliverRoute(_ location: CLLocation) {
        route = location
        calls.append(.deliverRoute(LocationCoordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)))
    }

    func endRoute() {
        route = nil
        calls.append(.endRoute)
    }
}
