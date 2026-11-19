#if DEBUG
    extension GPXError {
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
