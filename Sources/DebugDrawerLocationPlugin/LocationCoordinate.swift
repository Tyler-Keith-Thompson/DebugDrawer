#if DEBUG
    /// A latitude and longitude in degrees, as a plain value the Location plugin's snapshot,
    /// commands and store carry.
    struct LocationCoordinate: Codable, Equatable, Sendable {
        /// Degrees north of the equator, from -90 through 90.
        var latitude: Double
        /// Degrees east of the prime meridian, from -180 through 180.
        var longitude: Double
    }
#endif
