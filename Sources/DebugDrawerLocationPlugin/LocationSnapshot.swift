import Foundation

// Public because it is `LocationModel`'s `Snapshot`, and opaque: its fields stay internal, so a
// reader outside the module carries it whole, encoded. Coordinates are plain latitudes and
// longitudes, not CLLocations; the view formats them, and words an import's failure.

#if DEBUG
    /// Everything the Location Simulator shows, as a value: the spoofing switch, the coordinate
    /// fields, the location in effect, the presets and the route playback.
    ///
    /// ``LocationModel`` makes it; the plugin's view draws it. It is `Codable`, so a transport can
    /// carry it.
    public struct LocationSnapshot: Codable, Equatable, Sendable {
        /// Whether locations are simulated.
        var isEnabled = false
        /// The text in the Latitude field.
        var latitudeText = ""
        /// The text in the Longitude field.
        var longitudeText = ""
        /// The fixed coordinate kept, or nil for none.
        var coordinate: LocationCoordinate?
        /// The location managers are given now (the route's latest point while one plays, else the
        /// fixed coordinate, while spoofing is on), or nil while none is.
        var active: LocationCoordinate?
        /// The places listed under Presets.
        var presets: [LocationSimulator.PresetLocation] = []
        /// The routes to choose from: the samples, then the file imported last, if any.
        var routes: [Route] = []
        /// The ID of the route that plays.
        var routeID: Route.ID = ""
        /// How much faster than the track's own times the route plays.
        var speed = PlaybackSpeed.times1
        /// Where playback of the route stands.
        var playback = RoutePlayback.stopped
        /// Why the file imported last couldn't be played, or nil.
        var importFailure: GPXError?
    }
#else
    /// Release builds simulate nothing: this stand-in holds nothing.
    public struct LocationSnapshot: Codable, Equatable, Sendable {}
#endif
