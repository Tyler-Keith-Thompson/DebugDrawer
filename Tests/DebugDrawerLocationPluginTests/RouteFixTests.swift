@testable import DebugDrawerLocationPlugin
import Foundation
import Testing

@Suite
struct RouteFixTests {
    @Test("Each point takes the course and speed of the move that reaches it, and the first point the second's")
    func courseAndSpeed() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        // 0.001 degrees is 111.195 m along a meridian, and along the equator, on the mean sphere.
        let track = GPXTrack(points: [
            GPXTrackPoint(latitude: 0, longitude: 0, elevation: nil, time: start),
            GPXTrackPoint(latitude: 0.001, longitude: 0, elevation: nil, time: start.addingTimeInterval(10)),
            GPXTrackPoint(latitude: 0.001, longitude: 0.001, elevation: nil, time: start.addingTimeInterval(30)),
            GPXTrackPoint(latitude: 0, longitude: 0.001, elevation: nil, time: start.addingTimeInterval(40))
        ])
        let expectedOffsets: [TimeInterval] = [0, 10, 30, 40]
        let expectedCourses: [Double] = [0, 0, 90, 180]
        let expectedSpeeds: [Double] = [11.12, 11.12, 5.56, 11.12]

        let actual = track.fixes

        #expect(actual.map(\.offset) == expectedOffsets)
        #expect(actual.map { $0.course.rounded() } == expectedCourses)
        #expect(actual.map { ($0.speed * 100).rounded() / 100 } == expectedSpeeds)
    }

    @Test("Moving west of north gives a course below 360, not a negative one")
    func courseWraps() {
        let track = GPXTrack(points: [
            GPXTrackPoint(latitude: 0, longitude: 0, elevation: nil, time: nil),
            GPXTrackPoint(latitude: 0.001, longitude: -0.001, elevation: nil, time: nil)
        ])
        let expected: Double = 315

        let actual = track.fixes[1].course.rounded()

        #expect(actual == expected)
    }

    @Test("Points without times play a second apart")
    func untimed() {
        let track = GPXTrack(points: [
            GPXTrackPoint(latitude: 0, longitude: 0, elevation: nil, time: nil),
            GPXTrackPoint(latitude: 0.001, longitude: 0, elevation: nil, time: nil),
            GPXTrackPoint(latitude: 0.002, longitude: 0, elevation: nil, time: nil)
        ])
        let expectedOffsets: [TimeInterval] = [0, 1, 2]
        let expectedSpeed: Double = 111.2

        let actual = track.fixes

        #expect(GPXTrack.untimedInterval == 1)
        #expect(actual.map(\.offset) == expectedOffsets)
        #expect((actual[2].speed * 10).rounded() / 10 == expectedSpeed)
    }

    @Test("A track whose times go back, or that lacks one, plays a second apart instead")
    func inconsistentTimes() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let backwards = GPXTrack(points: [
            GPXTrackPoint(latitude: 0, longitude: 0, elevation: nil, time: start),
            GPXTrackPoint(latitude: 0.001, longitude: 0, elevation: nil, time: start.addingTimeInterval(-5))
        ])
        let missing = GPXTrack(points: [
            GPXTrackPoint(latitude: 0, longitude: 0, elevation: nil, time: start),
            GPXTrackPoint(latitude: 0.001, longitude: 0, elevation: nil, time: nil)
        ])
        let expected: [TimeInterval] = [0, 1]

        let actualBackwards = backwards.fixes.map(\.offset)
        let actualMissing = missing.fixes.map(\.offset)

        #expect(actualBackwards == expected)
        #expect(actualMissing == expected)
    }

    @Test("A one-point track has no course or speed; standing still has no course, and no time between points no speed")
    func noMove() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let single = GPXTrack(points: [GPXTrackPoint(latitude: 1, longitude: 1, elevation: nil, time: start)])
        let still = GPXTrack(points: [
            GPXTrackPoint(latitude: 1, longitude: 1, elevation: nil, time: start),
            GPXTrackPoint(latitude: 1, longitude: 1, elevation: nil, time: start.addingTimeInterval(5))
        ])
        let instant = GPXTrack(points: [
            GPXTrackPoint(latitude: 1, longitude: 1, elevation: nil, time: start),
            GPXTrackPoint(latitude: 1.001, longitude: 1, elevation: nil, time: start)
        ])

        let actualSingle = single.fixes
        let actualStill = still.fixes[1]
        let actualInstant = instant.fixes[1]

        #expect(actualSingle.map(\.course) == [-1])
        #expect(actualSingle.map(\.speed) == [-1])
        #expect(actualStill.course == -1)
        #expect(actualStill.speed == 0)
        #expect(actualInstant.course.rounded() == 0)
        #expect(actualInstant.speed == -1)
    }

    @Test("A fix's location carries its coordinate, elevation, course, speed and the timestamp given")
    func location() {
        let fix = RouteFix(
            point: GPXTrackPoint(latitude: 37.3349, longitude: -122.009, elevation: 45, time: nil), offset: 0, course: 90, speed: 12
        )
        let untimed = RouteFix(point: GPXTrackPoint(latitude: 1, longitude: 2, elevation: nil, time: nil), offset: 0, course: -1, speed: -1)
        let timestamp = Date(timeIntervalSince1970: 2_000_000)

        let actual = fix.location(at: timestamp)
        let actualUntimed = untimed.location(at: timestamp)

        #expect(actual.coordinate.latitude == 37.3349)
        #expect(actual.coordinate.longitude == -122.009)
        #expect(actual.altitude == 45)
        #expect(actual.course == 90)
        #expect(actual.speed == 12)
        #expect(actual.timestamp == timestamp)
        #expect(actualUntimed.verticalAccuracy < 0)
        #expect(actualUntimed.courseAccuracy < 0)
        #expect(actualUntimed.speedAccuracy < 0)
    }
}
