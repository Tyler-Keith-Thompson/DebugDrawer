#if DEBUG
    /// Why a GPX file couldn't be played. `Codable`, as the Location snapshot carries it; the
    /// Route section words it (`GPXError+Message.swift`).
    enum GPXError: Error, Codable, Equatable, Sendable {
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
    }
#endif
