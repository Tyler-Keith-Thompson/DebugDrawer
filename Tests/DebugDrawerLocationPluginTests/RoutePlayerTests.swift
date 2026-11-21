import CoreLocation
@testable import DebugDrawerLocationPlugin
import DebugDrawerTestSupport
import Foundation
import Testing

// Each test plays through a LocationSimulator of its own, over defaults of its own with spoofing
// on, to a manager it starts directly: nothing here swaps CLLocationManager's methods. The clock is a manual one,
// so no test waits.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct RoutePlayerTests {
    @Test("Playback delivers the points in order to a tracked manager's delegate, with course, speed and the moment delivered")
    func deliversInOrder() throws {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let track = GPXTrack(points: [
            GPXTrackPoint(latitude: 0, longitude: 0, elevation: 10, time: start),
            GPXTrackPoint(latitude: 0.001, longitude: 0, elevation: 11, time: start.addingTimeInterval(10)),
            GPXTrackPoint(latitude: 0.001, longitude: 0.001, elevation: 12, time: start.addingTimeInterval(20))
        ])
        let defaults = try #require(UserDefaults(suiteName: temporarySuiteName("RoutePlayerTests")))
        defaults.set(true, forKey: "com.debugdrawer.location.enabled")
        let simulator = LocationSimulator(defaults: defaults, service: RecordingLocationService())
        let manager = CLLocationManager()
        let delegate = RecordingLocationDelegate()
        manager.delegate = delegate
        simulator.startUpdatingLocation(for: manager)
        let now = Date(timeIntervalSince1970: 5_000_000)
        let scheduler = ManualPlaybackScheduler(now: now)
        let sut = RoutePlayer(routes: [Route(id: "test", name: "Test", fixes: track.fixes)], scheduler: scheduler, simulator: simulator)
        let expectedCoordinates: [[Double]] = [[0, 0], [0.001, 0], [0.001, 0.001]]
        let expectedAltitudes: [Double] = [10, 11, 12]
        let expectedCourses: [Double] = [0, 0, 90]
        let expectedSpeeds: [Double] = [11.12, 11.12, 11.12]
        let expectedTimestamps = [now, now.addingTimeInterval(10), now.addingTimeInterval(20)]

        sut.play()
        scheduler.advance(by: 20)

        let actual = delegate.locations
        #expect(actual.map { [$0.coordinate.latitude, $0.coordinate.longitude] } == expectedCoordinates)
        #expect(actual.map(\.altitude) == expectedAltitudes)
        #expect(actual.map { $0.course.rounded() } == expectedCourses)
        #expect(actual.map { ($0.speed * 100).rounded() / 100 } == expectedSpeeds)
        #expect(actual.map(\.timestamp) == expectedTimestamps)
        #expect(sut.playback == .finished)
    }

    @Test("At 2x the route is delivered in half the track's duration, and at 1x in all of it", arguments: [PlaybackSpeed.times1, .times2])
    func speedHalvesDuration(speed: PlaybackSpeed) throws {
        let start = Date(timeIntervalSince1970: 1_000_000)
        // 30 seconds from the first point to the last.
        let track = GPXTrack(points: [
            GPXTrackPoint(latitude: 0, longitude: 0, elevation: nil, time: start),
            GPXTrackPoint(latitude: 0.001, longitude: 0, elevation: nil, time: start.addingTimeInterval(10)),
            GPXTrackPoint(latitude: 0.002, longitude: 0, elevation: nil, time: start.addingTimeInterval(30))
        ])
        let defaults = try #require(UserDefaults(suiteName: temporarySuiteName("RoutePlayerTests")))
        defaults.set(true, forKey: "com.debugdrawer.location.enabled")
        let simulator = LocationSimulator(defaults: defaults, service: RecordingLocationService())
        let manager = CLLocationManager()
        let delegate = RecordingLocationDelegate()
        manager.delegate = delegate
        simulator.startUpdatingLocation(for: manager)
        let scheduler = ManualPlaybackScheduler(now: Date(timeIntervalSince1970: 5_000_000))
        let sut = RoutePlayer(routes: [Route(id: "test", name: "Test", fixes: track.fixes)], scheduler: scheduler, simulator: simulator)
        sut.speed = speed
        let expectedDuration: TimeInterval = 30 / speed.rawValue

        sut.play()
        scheduler.advance(by: expectedDuration - 1)
        let deliveredJustBefore = delegate.locations.count
        scheduler.advance(by: 1)

        #expect(deliveredJustBefore == 2)
        #expect(delegate.locations.count == 3)
        #expect(sut.playback == .finished)
        #expect(delegate.locations.last?.timestamp.timeIntervalSince(delegate.locations[0].timestamp) == expectedDuration)
    }

    @Test("Pause holds the points delivered; Play waits the whole gap to the next")
    func pauseAndResume() throws {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let track = GPXTrack(points: [
            GPXTrackPoint(latitude: 0, longitude: 0, elevation: nil, time: start),
            GPXTrackPoint(latitude: 0.001, longitude: 0, elevation: nil, time: start.addingTimeInterval(10)),
            GPXTrackPoint(latitude: 0.002, longitude: 0, elevation: nil, time: start.addingTimeInterval(20))
        ])
        let defaults = try #require(UserDefaults(suiteName: temporarySuiteName("RoutePlayerTests")))
        defaults.set(true, forKey: "com.debugdrawer.location.enabled")
        let simulator = LocationSimulator(defaults: defaults, service: RecordingLocationService())
        let manager = CLLocationManager()
        let delegate = RecordingLocationDelegate()
        manager.delegate = delegate
        simulator.startUpdatingLocation(for: manager)
        let scheduler = ManualPlaybackScheduler(now: Date(timeIntervalSince1970: 5_000_000))
        let sut = RoutePlayer(routes: [Route(id: "test", name: "Test", fixes: track.fixes)], scheduler: scheduler, simulator: simulator)

        sut.play()
        scheduler.advance(by: 5)
        sut.pause()
        scheduler.advance(by: 60)
        let whilePaused = delegate.locations.count
        let pausedState = sut.playback
        sut.play()
        scheduler.advance(by: 9)
        let beforeGap = delegate.locations.count
        scheduler.advance(by: 1)

        #expect(whilePaused == 1)
        #expect(pausedState == .paused(delivered: 1))
        #expect(beforeGap == 1)
        #expect(delegate.locations.count == 2)
        #expect(sut.playback == .playing(delivered: 2))
    }

    @Test("Stop cancels what is scheduled and puts the fixed coordinate back in effect")
    func stop() throws {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let track = GPXTrack(points: [
            GPXTrackPoint(latitude: 1, longitude: 1, elevation: nil, time: start),
            GPXTrackPoint(latitude: 2, longitude: 2, elevation: nil, time: start.addingTimeInterval(10))
        ])
        let defaults = try #require(UserDefaults(suiteName: temporarySuiteName("RoutePlayerTests")))
        defaults.set(true, forKey: "com.debugdrawer.location.enabled")
        defaults.set(51.5, forKey: "com.debugdrawer.location.latitude")
        defaults.set(-0.12, forKey: "com.debugdrawer.location.longitude")
        let simulator = LocationSimulator(defaults: defaults, service: RecordingLocationService())
        let manager = CLLocationManager()
        let delegate = RecordingLocationDelegate()
        manager.delegate = delegate
        simulator.startUpdatingLocation(for: manager)
        let scheduler = ManualPlaybackScheduler(now: Date(timeIntervalSince1970: 5_000_000))
        let sut = RoutePlayer(routes: [Route(id: "test", name: "Test", fixes: track.fixes)], scheduler: scheduler, simulator: simulator)
        let expectedLatitudes: [Double] = [1, 51.5]

        sut.play()
        let duringRoute = simulator.simulatedLocation?.coordinate.latitude
        sut.stop()
        scheduler.advance(by: 60)

        #expect(duringRoute == 1)
        #expect(delegate.locations.map(\.coordinate.latitude) == expectedLatitudes)
        #expect(simulator.simulatedLocation?.coordinate.latitude == 51.5)
        #expect(sut.playback == .stopped)
        #expect(scheduler.pendingCount == 0)
    }

    @Test("A speed changed while playing applies from the gap after the last point delivered")
    func changeSpeedWhilePlaying() throws {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let track = GPXTrack(points: [
            GPXTrackPoint(latitude: 0, longitude: 0, elevation: nil, time: start),
            GPXTrackPoint(latitude: 0.001, longitude: 0, elevation: nil, time: start.addingTimeInterval(100))
        ])
        let defaults = try #require(UserDefaults(suiteName: temporarySuiteName("RoutePlayerTests")))
        defaults.set(true, forKey: "com.debugdrawer.location.enabled")
        let simulator = LocationSimulator(defaults: defaults, service: RecordingLocationService())
        let manager = CLLocationManager()
        let delegate = RecordingLocationDelegate()
        manager.delegate = delegate
        simulator.startUpdatingLocation(for: manager)
        let scheduler = ManualPlaybackScheduler(now: Date(timeIntervalSince1970: 5_000_000))
        let sut = RoutePlayer(routes: [Route(id: "test", name: "Test", fixes: track.fixes)], scheduler: scheduler, simulator: simulator)

        sut.play()
        sut.speed = .times10
        scheduler.advance(by: 10)

        #expect(delegate.locations.count == 2)
        #expect(scheduler.pendingCount == 0)
    }

    @Test("Play after the route finishes starts it again from the first point")
    func replay() throws {
        let track = GPXTrack(points: [
            GPXTrackPoint(latitude: 1, longitude: 1, elevation: nil, time: nil),
            GPXTrackPoint(latitude: 2, longitude: 2, elevation: nil, time: nil)
        ])
        let defaults = try #require(UserDefaults(suiteName: temporarySuiteName("RoutePlayerTests")))
        defaults.set(true, forKey: "com.debugdrawer.location.enabled")
        let simulator = LocationSimulator(defaults: defaults, service: RecordingLocationService())
        let manager = CLLocationManager()
        let delegate = RecordingLocationDelegate()
        manager.delegate = delegate
        simulator.startUpdatingLocation(for: manager)
        let scheduler = ManualPlaybackScheduler(now: Date(timeIntervalSince1970: 5_000_000))
        let sut = RoutePlayer(routes: [Route(id: "test", name: "Test", fixes: track.fixes)], scheduler: scheduler, simulator: simulator)
        let expectedLatitudes: [Double] = [1, 2, 1]

        sut.play()
        scheduler.advance(by: 1)
        sut.play()

        #expect(delegate.locations.map(\.coordinate.latitude) == expectedLatitudes)
        #expect(sut.playback == .playing(delivered: 1))
    }

    @Test("A one-point route finishes as it starts")
    func onePoint() throws {
        let track = GPXTrack(points: [GPXTrackPoint(latitude: 1, longitude: 1, elevation: nil, time: nil)])
        let defaults = try #require(UserDefaults(suiteName: temporarySuiteName("RoutePlayerTests")))
        defaults.set(true, forKey: "com.debugdrawer.location.enabled")
        let simulator = LocationSimulator(defaults: defaults, service: RecordingLocationService())
        let scheduler = ManualPlaybackScheduler(now: Date(timeIntervalSince1970: 5_000_000))
        let sut = RoutePlayer(routes: [Route(id: "test", name: "Test", fixes: track.fixes)], scheduler: scheduler, simulator: simulator)

        sut.play()

        #expect(sut.playback == .finished)
        #expect(scheduler.pendingCount == 0)
    }

    @Test("An imported file joins the routes after the samples, replacing the one imported before, and is chosen")
    func importFile() throws {
        let track = GPXTrack(points: [GPXTrackPoint(latitude: 1, longitude: 1, elevation: nil, time: nil)])
        let defaults = try #require(UserDefaults(suiteName: temporarySuiteName("RoutePlayerTests")))
        defaults.set(true, forKey: "com.debugdrawer.location.enabled")
        let simulator = LocationSimulator(defaults: defaults, service: RecordingLocationService())
        let scheduler = ManualPlaybackScheduler(now: Date(timeIntervalSince1970: 5_000_000))
        let sut = RoutePlayer(scheduler: scheduler, simulator: simulator)
        let expectedNames = ["Apple Park Loop", "Golden Gate Bridge", "Evening Run"]

        sut.play()
        sut.importFile(.success(track), from: URL(filePath: "/tmp/Morning Run.gpx"))
        sut.importFile(.success(track), from: URL(filePath: "/tmp/Evening Run.gpx"))

        #expect(sut.routes.map(\.name) == expectedNames)
        #expect(sut.route.name == "Evening Run")
        #expect(sut.playback == .stopped)
        #expect(sut.importFailure == nil)
    }

    @Test("A file that can't be played shows why and leaves the route and its playback as they were")
    func importFailure() throws {
        let defaults = try #require(UserDefaults(suiteName: temporarySuiteName("RoutePlayerTests")))
        defaults.set(true, forKey: "com.debugdrawer.location.enabled")
        let simulator = LocationSimulator(defaults: defaults, service: RecordingLocationService())
        let scheduler = ManualPlaybackScheduler(now: Date(timeIntervalSince1970: 5_000_000))
        let sut = RoutePlayer(scheduler: scheduler, simulator: simulator)

        sut.play()
        sut.importFile(.failure(.notGPX), from: URL(filePath: "/tmp/route.kml"))

        #expect(sut.importFailure == .notGPX)
        #expect(sut.route.name == "Apple Park Loop")
        #expect(sut.playback == .playing(delivered: 1))
        #expect(sut.routes.count == 2)
    }

    @Test("Choosing another route stops playback and clears an import's failure")
    func select() throws {
        let defaults = try #require(UserDefaults(suiteName: temporarySuiteName("RoutePlayerTests")))
        defaults.set(true, forKey: "com.debugdrawer.location.enabled")
        let simulator = LocationSimulator(defaults: defaults, service: RecordingLocationService())
        let scheduler = ManualPlaybackScheduler(now: Date(timeIntervalSince1970: 5_000_000))
        let sut = RoutePlayer(scheduler: scheduler, simulator: simulator)

        sut.play()
        sut.importFile(.failure(.noPoints), from: URL(filePath: "/tmp/empty.gpx"))
        sut.select("sample:Golden Gate Bridge")

        #expect(sut.route.name == "Golden Gate Bridge")
        #expect(sut.playback == .stopped)
        #expect(sut.importFailure == nil)
        #expect(scheduler.pendingCount == 0)
    }
}
