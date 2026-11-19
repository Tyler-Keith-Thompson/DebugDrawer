#if DEBUG
    import Foundation

    /// A route read from a GPX file: its points in the order the file lists them.
    struct GPXTrack: Equatable, Sendable {
        /// The points, in document order.
        let points: [GPXTrackPoint]

        /// Parses a GPX document.
        ///
        /// The points are the file's track points (`trkpt`); a file with none gives its route points
        /// (`rtept`), and one with neither its waypoints (`wpt`).
        ///
        /// - Parameter data: The GPX document.
        /// - Throws: ``GPXError`` when the document isn't well-formed XML, isn't GPX, has a point
        ///   whose coordinate, elevation or time can't be read, or has no points.
        /// - Complexity: O(*n*) in the length of the document.
        init(data: Data) throws(GPXError) {
            points = try GPXParser.points(in: data)
        }

        init(points: [GPXTrackPoint]) {
            self.points = points
        }
    }

    /// One point of a ``GPXTrack``.
    struct GPXTrackPoint: Codable, Equatable, Sendable {
        /// Degrees north of the equator, from -90 through 90.
        let latitude: Double
        /// Degrees east of the prime meridian, from -180 through 180.
        let longitude: Double
        /// Meters above sea level, or `nil` when the point has no `ele`.
        let elevation: Double?
        /// When the point was recorded, or `nil` when it has no `time`.
        let time: Date?
    }
#endif
