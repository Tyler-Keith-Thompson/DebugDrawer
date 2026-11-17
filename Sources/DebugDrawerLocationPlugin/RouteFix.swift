#if DEBUG
    import CoreLocation

    /// One point of a route as playback delivers it: where it is, when it comes in the route, and
    /// the heading and speed of the move that reaches it.
    struct RouteFix: Equatable, Sendable {
        let point: GPXTrackPoint
        /// Seconds from the route's first point to this one.
        let offset: TimeInterval
        /// Degrees clockwise from true north, or -1 where no move gives a heading.
        let course: CLLocationDirection
        /// Meters per second, or -1 where no move gives a speed.
        let speed: CLLocationSpeed

        /// The location a tracked manager is given for this fix.
        ///
        /// - Parameter timestamp: When it is delivered.
        func location(at timestamp: Date) -> CLLocation {
            CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude),
                altitude: point.elevation ?? 0,
                horizontalAccuracy: 5,
                // Negative marks the altitude invalid, for a point with no elevation.
                verticalAccuracy: point.elevation == nil ? -1 : 5,
                course: course,
                courseAccuracy: course < 0 ? -1 : 5,
                speed: speed,
                speedAccuracy: speed < 0 ? -1 : 0.5,
                timestamp: timestamp
            )
        }
    }

    extension GPXTrack {
        /// The seconds between points of a track that has no times: a reading a second, as a
        /// phone's location updates come while it moves.
        static let untimedInterval: TimeInterval = 1

        /// The track's points with their offsets, courses and speeds.
        ///
        /// Offsets come from the points' times when every point has one and they never go back;
        /// otherwise the points are ``untimedInterval`` apart. A point's course and speed are those
        /// of the move from the point before it, and the first point takes the second's, so a
        /// route starts already heading somewhere. A one-point track has neither.
        ///
        /// - Complexity: O(*n*) in the number of points.
        var fixes: [RouteFix] {
            let offsets = offsets
            let moves = points.indices.dropFirst().map { index in
                Move(
                    from: points[index - 1], to: points[index], seconds: offsets[index] - offsets[index - 1]
                )
            }
            return points.indices.map { index in
                let move = index == 0 ? moves.first : moves[index - 1]
                return RouteFix(point: points[index], offset: offsets[index], course: move?.course ?? -1, speed: move?.speed ?? -1)
            }
        }

        private var offsets: [TimeInterval] {
            let times = points.compactMap(\.time)
            let isTimed = times.count == points.count && zip(times, times.dropFirst()).allSatisfy { $0 <= $1 }
            guard isTimed, let start = times.first else {
                return points.indices.map { TimeInterval($0) * Self.untimedInterval }
            }
            return times.map { $0.timeIntervalSince(start) }
        }
    }

    /// The step between two consecutive points.
    private struct Move {
        let course: CLLocationDirection
        let speed: CLLocationSpeed

        init(from start: GPXTrackPoint, to end: GPXTrackPoint, seconds: TimeInterval) {
            let distance = Self.distance(from: start, to: end)
            // Standing still gives no heading; two points at one moment give no speed.
            course = distance > 0 ? Self.bearing(from: start, to: end) : -1
            speed = seconds > 0 ? distance / seconds : -1
        }

        // A plain great-circle model, the haversine distance and the initial bearing on a sphere of
        // the Earth's mean radius: within half a percent of the ellipsoid, plenty for a heading and
        // a speed between points a few meters to a few kilometers apart. Written here rather than
        // through CLLocation.distance(from:), which gives no bearing.
        private static let earthRadius: Double = 6_371_008.8

        /// Meters along the great circle between the points.
        private static func distance(from start: GPXTrackPoint, to end: GPXTrackPoint) -> Double {
            let phi1 = start.latitude * .pi / 180, phi2 = end.latitude * .pi / 180
            let deltaPhi = phi2 - phi1
            let deltaLambda = (end.longitude - start.longitude) * .pi / 180
            let haversine = sin(deltaPhi / 2) * sin(deltaPhi / 2) + cos(phi1) * cos(phi2) * sin(deltaLambda / 2) * sin(deltaLambda / 2)
            return 2 * earthRadius * atan2(haversine.squareRoot(), (1 - haversine).squareRoot())
        }

        /// Degrees clockwise from true north, from 0 up to 360, of the great circle leaving the
        /// start toward the end.
        private static func bearing(from start: GPXTrackPoint, to end: GPXTrackPoint) -> Double {
            let phi1 = start.latitude * .pi / 180, phi2 = end.latitude * .pi / 180
            let deltaLambda = (end.longitude - start.longitude) * .pi / 180
            let east = sin(deltaLambda) * cos(phi2)
            let north = cos(phi1) * sin(phi2) - sin(phi1) * cos(phi2) * cos(deltaLambda)
            let degrees = atan2(east, north) * 180 / .pi
            return (degrees + 360).truncatingRemainder(dividingBy: 360)
        }
    }
#endif
