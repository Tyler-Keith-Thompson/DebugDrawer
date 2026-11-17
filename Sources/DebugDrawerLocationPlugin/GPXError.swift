#if DEBUG
    /// Why a GPX file couldn't be played.
    enum GPXError: Error, Equatable, Sendable {
        /// The file couldn't be read.
        case unreadable
        /// The file isn't well-formed XML.
        case malformedXML
        /// The file is XML whose root element isn't `gpx`.
        case notGPX
        /// A point's `lat` or `lon` is missing, isn't a number or is out of range.
        case invalidCoordinate
        /// A point's `ele` isn't a number.
        case invalidElevation
        /// A point's `time` isn't an ISO 8601 date.
        case invalidTime
        /// The file has no track, route or waypoint points.
        case noPoints

        /// What went wrong, in a sentence shown beside the import.
        var message: String {
            switch self {
            case .unreadable: "The file couldn't be read."
            case .malformedXML: "The file isn't well-formed XML."
            case .notGPX: "The file isn't GPX: its root element isn't <gpx>."
            case .invalidCoordinate: "A point's latitude or longitude is missing or out of range."
            case .invalidElevation: "A point's elevation isn't a number."
            case .invalidTime: "A point's time isn't an ISO 8601 date."
            case .noPoints: "The file has no track, route or waypoint points."
            }
        }
    }
#endif
