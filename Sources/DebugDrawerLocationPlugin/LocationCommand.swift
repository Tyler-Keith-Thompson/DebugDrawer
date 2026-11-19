import Foundation

// Public because it is `LocationModel`'s `Command`, and opaque: an enum's cases share its access
// level, and a preset or a route ID is the plugin's own type, so the public type is a struct
// around the internal enum.

#if DEBUG
    /// Something the Location Simulator's view asks ``LocationModel`` to do: turn spoofing on or
    /// off, type or set a coordinate, choose a preset, or pick, play, pause, stop or import a
    /// route. `Codable`, so a transport can carry it.
    public struct LocationCommand: Codable, Sendable {
        /// What to do.
        enum Action: Codable, Equatable, Sendable {
            /// Turns spoofing on or off; off stops a route playing.
            case setEnabled(Bool)
            /// Puts the text in the Latitude field, and spoofs the typed coordinate once both
            /// fields hold numbers in range.
            case setLatitudeText(String)
            /// Puts the text in the Longitude field, and spoofs the typed coordinate once both
            /// fields hold numbers in range.
            case setLongitudeText(String)
            /// Spoofs a coordinate, shown in the fields, or with nil clears the one kept and the
            /// fields. One out of range is ignored.
            case setCoordinate(LocationCoordinate?)
            /// Spoofs a preset's coordinate, shown in the fields.
            case choosePreset(LocationSimulator.PresetLocation)
            /// Stops playback and chooses another route.
            case selectRoute(Route.ID)
            /// Sets how much faster than the track's own times the route plays.
            case setSpeed(PlaybackSpeed)
            /// Plays the route from its first point, or carries on after a pause.
            case play
            /// Holds the last point delivered until Play.
            case pause
            /// Ends playback; managers go back to the fixed coordinate, if one is set.
            case stop
            /// Reads a GPX file and chooses its route, or keeps why it can't be played.
            case importRoute(URL)
        }

        let action: Action

        init(_ action: Action) {
            self.action = action
        }
    }
#else
    /// Release builds simulate nothing: this stand-in asks for nothing.
    public struct LocationCommand: Codable, Sendable {}
#endif
