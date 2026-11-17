@testable import DebugDrawerLocationPlugin
import Foundation
import Testing

@Suite
struct GPXTrackTests {
    @Test("A GPX fixture parses into its track points in document order, with their elevations and times")
    func parsesTrackPoints() throws {
        let gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Test" xmlns="http://www.topografix.com/GPX/1/1">
          <trk><name>Morning</name><trkseg>
            <trkpt lat="37.3349" lon="-122.0090"><ele>45.5</ele><time>2026-01-01T09:00:00Z</time></trkpt>
            <trkpt lat="37.3359" lon="-122.0090"><ele>46</ele><time>2026-01-01T09:00:10Z</time></trkpt>
          </trkseg><trkseg>
            <trkpt lat="37.3359" lon="-122.0080"><time>2026-01-01T09:00:25.500Z</time></trkpt>
          </trkseg></trk>
        </gpx>
        """
        let start = Date(timeIntervalSince1970: 1_767_258_000)
        let expected = [
            GPXTrackPoint(latitude: 37.3349, longitude: -122.0090, elevation: 45.5, time: start),
            GPXTrackPoint(latitude: 37.3359, longitude: -122.0090, elevation: 46, time: start.addingTimeInterval(10)),
            GPXTrackPoint(latitude: 37.3359, longitude: -122.0080, elevation: nil, time: start.addingTimeInterval(25.5))
        ]

        let actual = try GPXTrack(data: Data(gpx.utf8)).points

        #expect(actual == expected)
    }

    @Test("A file with track points plays them, not its waypoints or route points")
    func prefersTrackPoints() throws {
        let gpx = """
        <gpx version="1.1"><wpt lat="1" lon="1"/><rte><rtept lat="2" lon="2"/></rte><trk><trkseg><trkpt lat="3" lon="3"/></trkseg></trk></gpx>
        """
        let expected: [Double] = [3]

        let actual = try GPXTrack(data: Data(gpx.utf8)).points.map(\.latitude)

        #expect(actual == expected)
    }

    @Test("A file with no track points gives its route points, and one with neither its waypoints")
    func fallsBack() throws {
        let route = #"<gpx><wpt lat="1" lon="1"/><rte><rtept lat="2" lon="2"/><rtept lat="4" lon="4"/></rte></gpx>"#
        let waypoints = #"<gpx><wpt lat="1" lon="1"/><wpt lat="5" lon="5"/></gpx>"#
        let expectedRoute: [Double] = [2, 4]
        let expectedWaypoints: [Double] = [1, 5]

        let actualRoute = try GPXTrack(data: Data(route.utf8)).points.map(\.latitude)
        let actualWaypoints = try GPXTrack(data: Data(waypoints.utf8)).points.map(\.latitude)

        #expect(actualRoute == expectedRoute)
        #expect(actualWaypoints == expectedWaypoints)
    }

    @Test("Prefixed elements read as GPX's own")
    func namespacePrefix() throws {
        let gpx = #"<g:gpx xmlns:g="http://www.topografix.com/GPX/1/1"><g:wpt lat="1" lon="2"><g:ele>3</g:ele></g:wpt></g:gpx>"#
        let expected = [GPXTrackPoint(latitude: 1, longitude: 2, elevation: 3, time: nil)]

        let actual = try GPXTrack(data: Data(gpx.utf8)).points

        #expect(actual == expected)
    }

    @Test("Coordinates on the edges of their ranges parse")
    func coordinateBounds() throws {
        let gpx = #"<gpx><wpt lat="-90" lon="-180"/><wpt lat="90" lon="180"/></gpx>"#
        let expected = [
            GPXTrackPoint(latitude: -90, longitude: -180, elevation: nil, time: nil),
            GPXTrackPoint(latitude: 90, longitude: 180, elevation: nil, time: nil)
        ]

        let actual = try GPXTrack(data: Data(gpx.utf8)).points

        #expect(actual == expected)
    }

    @Test(
        "Malformed GPX throws the error that says what is wrong with it",
        arguments: [
            ("", GPXError.malformedXML),
            ("<gpx><trk>", .malformedXML),
            ("<kml><wpt lat=\"1\" lon=\"1\"/></kml>", .notGPX),
            ("<gpx><wpt lon=\"1\"/></gpx>", .invalidCoordinate),
            ("<gpx><wpt lat=\"north\" lon=\"1\"/></gpx>", .invalidCoordinate),
            ("<gpx><wpt lat=\"90.5\" lon=\"1\"/></gpx>", .invalidCoordinate),
            ("<gpx><wpt lat=\"1\" lon=\"-180.5\"/></gpx>", .invalidCoordinate),
            ("<gpx><wpt lat=\"1\" lon=\"1\"><ele>high</ele></wpt></gpx>", .invalidElevation),
            ("<gpx><wpt lat=\"1\" lon=\"1\"><time>yesterday</time></wpt></gpx>", .invalidTime),
            ("<gpx><trk><name>Empty</name></trk></gpx>", .noPoints)
        ]
    )
    func malformed(gpx: String, expected: GPXError) {
        func parse() throws(GPXError) {
            _ = try GPXTrack(data: Data(gpx.utf8))
        }

        #expect(throws: expected, performing: parse)
    }

    @Test("Each bundled sample parses into a timed track of more than one point")
    func samples() throws {
        let samples = [GPXSamples.appleParkLoop, GPXSamples.goldenGateBridge]
        let expectedCounts = [25, 12]

        let actual = try samples.map { try GPXTrack(data: Data($0.utf8)).points }

        #expect(actual.map(\.count) == expectedCounts)
        #expect(actual.allSatisfy { $0.allSatisfy { $0.time != nil } })
        #expect(Route.samples.map(\.name) == ["Apple Park Loop", "Golden Gate Bridge"])
    }

    @Test("Each error reads as a sentence")
    func messages() {
        let errors: [GPXError] = [.unreadable, .malformedXML, .notGPX, .invalidCoordinate, .invalidElevation, .invalidTime, .noPoints]

        let actual = errors.map(\.message)

        #expect(Set(actual).count == errors.count)
        #expect(actual.allSatisfy { $0.hasSuffix(".") })
    }

    @Test("A file that can't be read throws Unreadable")
    func unreadable() {
        let url = URL(filePath: "/nonexistent/route-\(UUID().uuidString).gpx")
        func read() throws(GPXError) {
            _ = try GPXTrack(contentsOf: url)
        }

        #expect(throws: GPXError.unreadable, performing: read)
    }
}
