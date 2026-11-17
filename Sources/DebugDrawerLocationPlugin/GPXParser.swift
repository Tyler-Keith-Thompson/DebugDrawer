#if DEBUG
    import Foundation

    /// Reads the points of a GPX document with Foundation's `XMLParser`, which streams elements to
    /// a delegate; this is that delegate, used once per document.
    final class GPXParser: NSObject, XMLParserDelegate {
        private enum Kind: String {
            case track = "trkpt"
            case route = "rtept"
            case waypoint = "wpt"
        }

        /// The point being read, from its start tag to its end tag.
        private struct OpenPoint {
            let kind: Kind
            let latitude: Double
            let longitude: Double
            var elevation: Double?
            var time: Date?
        }

        private var isFirstElement = true
        private var open: OpenPoint?
        /// The text of the `ele` or `time` being read inside a point, or nil outside one.
        private var text: String?
        private var points: [Kind: [GPXTrackPoint]] = [:]
        private var failure: GPXError?

        /// The document's track points, else its route points, else its waypoints.
        static func points(in data: Data) throws(GPXError) -> [GPXTrackPoint] {
            let delegate = GPXParser()
            let parser = XMLParser(data: data)
            // Element names arrive without their prefix, so `<gpx:trkpt>` reads as `trkpt`.
            parser.shouldProcessNamespaces = true
            parser.delegate = delegate
            let isParsed = parser.parse()
            if let failure = delegate.failure { throw failure }
            guard isParsed else { throw .malformedXML }
            if delegate.isFirstElement { throw .malformedXML }
            let found = [Kind.track, .route, .waypoint].lazy.compactMap { delegate.points[$0] }.first { !$0.isEmpty }
            guard let found else { throw .noPoints }
            return found
        }

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName: String?,
            attributes: [String: String] = [:]
        ) {
            if isFirstElement {
                isFirstElement = false
                guard elementName == "gpx" else { return fail(.notGPX, parser) }
            }
            if let kind = Kind(rawValue: elementName) {
                guard let latitude = attributes["lat"].flatMap(Double.init), (-90 ... 90).contains(latitude),
                      let longitude = attributes["lon"].flatMap(Double.init), (-180 ... 180).contains(longitude)
                else { return fail(.invalidCoordinate, parser) }
                open = OpenPoint(kind: kind, latitude: latitude, longitude: longitude)
            } else if open != nil, elementName == "ele" || elementName == "time" {
                text = ""
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            text?.append(string)
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
            let value = text?.trimmingCharacters(in: .whitespacesAndNewlines)
            text = nil
            switch elementName {
            case "ele" where value != nil:
                guard let elevation = value.flatMap(Double.init) else { return fail(.invalidElevation, parser) }
                open?.elevation = elevation
            case "time" where value != nil:
                guard let time = value.flatMap(Date.init(gpxTime:)) else { return fail(.invalidTime, parser) }
                open?.time = time
            case Kind.track.rawValue, Kind.route.rawValue, Kind.waypoint.rawValue:
                guard let point = open else { return }
                points[point.kind, default: []].append(
                    GPXTrackPoint(latitude: point.latitude, longitude: point.longitude, elevation: point.elevation, time: point.time)
                )
                open = nil
            default:
                break
            }
        }

        private func fail(_ error: GPXError, _ parser: XMLParser) {
            failure = error
            parser.abortParsing()
        }
    }

    extension Date {
        /// An ISO 8601 date and time, as GPX writes them, with or without fractional seconds.
        fileprivate init?(gpxTime text: String) {
            if let date = try? Date(text, strategy: .iso8601) {
                self = date
            } else if let date = try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) {
                self = date
            } else {
                return nil
            }
        }
    }
#endif
