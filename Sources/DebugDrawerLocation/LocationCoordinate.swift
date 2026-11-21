import CoreLocation

// A plain value rather than `CLLocationCoordinate2D`, which isn't `Codable`: the Location plugin's
// snapshot, commands and store carry it, and so do the spoofing capability's, across the process
// boundary. It lives here, with the capability, so the drawer's half and the release build's half
// carry one vocabulary.

/// A latitude and longitude in degrees, as a plain value the Location plugin and the location
/// spoofing capability carry.
public struct LocationCoordinate: Codable, Equatable, Hashable, Sendable {
    /// Degrees north of the equator, from -90 through 90.
    public var latitude: Double
    /// Degrees east of the prime meridian, from -180 through 180.
    public var longitude: Double

    /// A coordinate. It may be out of range: check ``isValid`` before using it as a location.
    ///
    /// - Parameters:
    ///   - latitude: Degrees north of the equator.
    ///   - longitude: Degrees east of the prime meridian.
    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// The coordinate Core Location's `coordinate` holds.
    ///
    /// - Parameter coordinate: A Core Location coordinate.
    public init(_ coordinate: CLLocationCoordinate2D) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    /// Whether it is a place on Earth: latitude in -90...90 and longitude in -180...180, neither
    /// one NaN.
    public var isValid: Bool {
        (-90.0 ... 90.0).contains(latitude) && (-180.0 ... 180.0).contains(longitude)
    }
}
