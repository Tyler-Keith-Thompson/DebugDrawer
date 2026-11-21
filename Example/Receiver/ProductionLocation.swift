import CoreLocation
import DebugDrawerLocation
import Foundation

/// The example's store finder: where it searches from, and the fraud signal the app's own checks
/// read, both following a sidecar's location spoof for its session through `LocationSpoofing`.
///
/// The example asks for no location permission, so the device's location is a fixed reading (Apple
/// Park); a real app passes each of Core Location's deliveries through the spoofing's
/// `locations(replacing:)`, as Refresh passes this one.
@MainActor
final class ProductionLocation: ObservableObject {
    /// The device's location as the example has it.
    static let deviceLocation = CLLocation(latitude: 37.3349, longitude: -122.0090)

    /// Where the store finder searches from: the device's location, or the sidecar's while it
    /// spoofs.
    @Published private(set) var location = ProductionLocation.deviceLocation
    /// The fraud signal: while it is on, what the store finder searches from isn't where the device
    /// is.
    @Published private(set) var isSpoofed = false

    /// Told by the spoofing as a spoof starts, moves and ends.
    func spoofingDidChange(_ spoofed: CLLocation?) {
        isSpoofed = spoofed != nil
        location = spoofed ?? Self.deviceLocation
    }

    /// Reads the device's location again, through `spoofing`.
    func refresh(through spoofing: LocationSpoofing) {
        location = spoofing.location(replacing: Self.deviceLocation) ?? Self.deviceLocation
    }

    /// The location as the screen says it.
    var summary: String {
        String(format: "%.4f, %.4f", location.coordinate.latitude, location.coordinate.longitude)
    }
}
