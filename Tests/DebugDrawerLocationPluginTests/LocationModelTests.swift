import Combine
import CoreLocation
import DebugDrawer
@testable import DebugDrawerLocationPlugin
import DebugDrawerTestSupport
import Foundation
import Testing

// Each test drives a LocationModel of its own through a direct transport, over a fake override
// that records what it is told, a fake interception that swaps nothing, a fake GPX reader and a
// manual playback clock: nothing here swaps CLLocationManager's methods, reads a file or waits.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct LocationModelTests {
    @Test("The snapshot survives a JSON round trip, with spoofing on, a route paused and an import failed")
    func snapshotRoundTrip() throws {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let fixes = GPXTrack(points: [
            GPXTrackPoint(latitude: 37.3349, longitude: -122.009, elevation: 45, time: start),
            GPXTrackPoint(latitude: 37.3359, longitude: -122.008, elevation: nil, time: start.addingTimeInterval(10))
        ]).fixes
        let simulator = FakeLocationOverride(isEnabled: true, coordinate: CLLocationCoordinate2D(latitude: 51.5, longitude: -0.12))
        let model = LocationModel(
            simulator: simulator, interception: FakeLocationInterception(), files: FakeGPXFileReading(),
            scheduler: ManualPlaybackScheduler(now: start), routes: [Route(id: "test", name: "Test", fixes: fixes)]
        )
        let sut = DebugDrawerPluginTransport.direct(to: model)
        sut.send(LocationCommand(.setSpeed(.times5)))
        sut.send(LocationCommand(.play))
        sut.send(LocationCommand(.pause))
        sut.send(LocationCommand(.importRoute(URL(fileURLWithPath: "/tmp/missing.gpx"))))
        let expected = sut.snapshot

        let data = try JSONEncoder().encode(sut.snapshot)
        let actual = try JSONDecoder().decode(LocationSnapshot.self, from: data)

        #expect(actual == expected)
        #expect(actual.playback == .paused(delivered: 1))
        #expect(actual.importFailure == .unreadable)
        #expect(actual.active == LocationCoordinate(latitude: 37.3349, longitude: -122.009))
    }

    @Test("Every command survives a JSON round trip")
    func commandRoundTrip() throws {
        let expected: [LocationCommand.Action] = [
            .setEnabled(true),
            .setLatitudeText("48.8566"),
            .setLongitudeText("-2.35"),
            .setCoordinate(LocationCoordinate(latitude: 1, longitude: 2)),
            .setCoordinate(nil),
            .choosePreset(LocationSimulator.PresetLocation(name: "Paris", latitude: 48.8566, longitude: 2.3522)),
            .selectRoute("sample:Golden Gate Bridge"),
            .setSpeed(.times10),
            .play,
            .pause,
            .stop,
            .importRoute(URL(fileURLWithPath: "/tmp/drive.gpx"))
        ]

        let data = try JSONEncoder().encode(expected.map { LocationCommand($0) })
        let actual = try JSONDecoder().decode([LocationCommand].self, from: data).map(\.action)

        #expect(actual == expected)
    }

    @Test("Turning spoofing on, setting a coordinate, clearing it and turning spoofing off each reach the override")
    func setAndClearReachTheOverride() {
        let simulator = FakeLocationOverride()
        let model = LocationModel(
            simulator: simulator, interception: FakeLocationInterception(), files: FakeGPXFileReading(),
            scheduler: ManualPlaybackScheduler(now: Date(timeIntervalSince1970: 0))
        )
        let sut = DebugDrawerPluginTransport.direct(to: model)
        let paris = LocationCoordinate(latitude: 48.8566, longitude: 2.3522)
        let expectedCalls: [FakeLocationOverride.Call] = [
            .setEnabled(true), .setCoordinate(paris), .setCoordinate(nil), .setEnabled(false)
        ]

        sut.send(LocationCommand(.setEnabled(true)))
        sut.send(LocationCommand(.setCoordinate(paris)))
        let whileSet = sut.snapshot
        sut.send(LocationCommand(.setCoordinate(nil)))
        let whileCleared = sut.snapshot
        sut.send(LocationCommand(.setEnabled(false)))
        let actual = sut.snapshot

        #expect(simulator.calls == expectedCalls)
        #expect(whileSet.isEnabled)
        #expect(whileSet.coordinate == paris)
        #expect(whileSet.active == paris)
        #expect([whileSet.latitudeText, whileSet.longitudeText] == ["48.8566", "2.3522"])
        #expect(whileCleared.coordinate == nil)
        #expect(whileCleared.active == nil)
        #expect([whileCleared.latitudeText, whileCleared.longitudeText] == ["", ""])
        #expect(!actual.isEnabled)
    }

    @Test("A coordinate out of range is ignored rather than trapping, and the fields keep what they held")
    func coordinateOutOfRangeIgnored() {
        let simulator = FakeLocationOverride(isEnabled: true, coordinate: CLLocationCoordinate2D(latitude: 10, longitude: 20))
        let model = LocationModel(
            simulator: simulator, interception: FakeLocationInterception(), files: FakeGPXFileReading(),
            scheduler: ManualPlaybackScheduler(now: Date(timeIntervalSince1970: 0))
        )
        let sut = DebugDrawerPluginTransport.direct(to: model)
        let expected = LocationCoordinate(latitude: 10, longitude: 20)

        sut.send(LocationCommand(.setCoordinate(LocationCoordinate(latitude: 91, longitude: 0))))
        sut.send(LocationCommand(.setCoordinate(LocationCoordinate(latitude: 0, longitude: -181))))

        #expect(simulator.calls.isEmpty)
        #expect(sut.snapshot.coordinate == expected)
        #expect([sut.snapshot.latitudeText, sut.snapshot.longitudeText] == ["10.0", "20.0"])
    }

    @Test("Typing spoofs the coordinate only once both fields hold numbers in range")
    func typingAppliesWhenValid() {
        let simulator = FakeLocationOverride(isEnabled: true)
        let model = LocationModel(
            simulator: simulator, interception: FakeLocationInterception(), files: FakeGPXFileReading(),
            scheduler: ManualPlaybackScheduler(now: Date(timeIntervalSince1970: 0))
        )
        let sut = DebugDrawerPluginTransport.direct(to: model)
        let paris = LocationCoordinate(latitude: 48.8566, longitude: 2.3522)
        let expectedCalls: [FakeLocationOverride.Call] = [.setCoordinate(paris)]

        sut.send(LocationCommand(.setLatitudeText("48.8566")))
        sut.send(LocationCommand(.setLongitudeText("-")))
        sut.send(LocationCommand(.setLongitudeText("2.3522")))
        sut.send(LocationCommand(.setLatitudeText("91")))

        #expect(simulator.calls == expectedCalls)
        #expect([sut.snapshot.latitudeText, sut.snapshot.longitudeText] == ["91", "2.3522"])
        #expect(sut.snapshot.active == paris)
    }

    @Test("The presets are listed, and choosing one spoofs its coordinate and shows it in the fields")
    func choosingAPreset() throws {
        let simulator = FakeLocationOverride(isEnabled: true)
        let model = LocationModel(
            simulator: simulator, interception: FakeLocationInterception(), files: FakeGPXFileReading(),
            scheduler: ManualPlaybackScheduler(now: Date(timeIntervalSince1970: 0))
        )
        let sut = DebugDrawerPluginTransport.direct(to: model)
        let expectedNames = ["New York, USA", "London, UK", "Tokyo, Japan", "Sydney, Australia", "Sao Paulo, Brazil"]
        let tokyo = LocationCoordinate(latitude: 35.6762, longitude: 139.6503)
        let expectedCalls: [FakeLocationOverride.Call] = [.setCoordinate(tokyo)]

        let preset = try #require(sut.snapshot.presets.first { $0.name == "Tokyo, Japan" })
        sut.send(LocationCommand(.choosePreset(preset)))

        #expect(sut.snapshot.presets.map(\.name) == expectedNames)
        #expect(simulator.calls == expectedCalls)
        #expect([sut.snapshot.latitudeText, sut.snapshot.longitudeText] == ["35.6762", "139.6503"])
        #expect(sut.snapshot.active == tokyo)
    }

    @Test("Play delivers the route's points on the clock, each announced through the transport; Pause holds; Stop goes back to the coordinate")
    func routePlayback() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let fixes = GPXTrack(points: [
            GPXTrackPoint(latitude: 1, longitude: 1, elevation: nil, time: start),
            GPXTrackPoint(latitude: 2, longitude: 2, elevation: nil, time: start.addingTimeInterval(10)),
            GPXTrackPoint(latitude: 3, longitude: 3, elevation: nil, time: start.addingTimeInterval(20))
        ]).fixes
        let simulator = FakeLocationOverride(isEnabled: true, coordinate: CLLocationCoordinate2D(latitude: 50, longitude: 50))
        let scheduler = ManualPlaybackScheduler(now: start)
        let model = LocationModel(
            simulator: simulator, interception: FakeLocationInterception(), files: FakeGPXFileReading(),
            scheduler: scheduler, routes: [Route(id: "test", name: "Test", fixes: fixes)]
        )
        let sut = DebugDrawerPluginTransport.direct(to: model)
        var changes = 0
        let watching = sut.objectWillChange.sink { changes += 1 }
        let expectedCalls: [FakeLocationOverride.Call] = [
            .deliverRoute(LocationCoordinate(latitude: 1, longitude: 1)),
            .deliverRoute(LocationCoordinate(latitude: 2, longitude: 2)),
            .endRoute
        ]

        sut.send(LocationCommand(.play))
        let changesBeforeClock = changes
        scheduler.advance(by: 10)
        let afterTen = sut.snapshot
        sut.send(LocationCommand(.pause))
        scheduler.advance(by: 60)
        let paused = sut.snapshot
        sut.send(LocationCommand(.stop))
        let actual = sut.snapshot
        watching.cancel()

        #expect(simulator.calls == expectedCalls)
        #expect(changes > changesBeforeClock)
        #expect(afterTen.active == LocationCoordinate(latitude: 2, longitude: 2))
        #expect(afterTen.playback == .playing(delivered: 2))
        #expect(paused.playback == .paused(delivered: 2))
        #expect(paused.active == LocationCoordinate(latitude: 2, longitude: 2))
        #expect(actual.playback == .stopped)
        #expect(actual.active == LocationCoordinate(latitude: 50, longitude: 50))
    }

    @Test("Turning spoofing off stops a route playing before the switch goes off")
    func turningOffStopsTheRoute() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let fixes = GPXTrack(points: [
            GPXTrackPoint(latitude: 1, longitude: 1, elevation: nil, time: start),
            GPXTrackPoint(latitude: 2, longitude: 2, elevation: nil, time: start.addingTimeInterval(10))
        ]).fixes
        let simulator = FakeLocationOverride(isEnabled: true)
        let scheduler = ManualPlaybackScheduler(now: start)
        let model = LocationModel(
            simulator: simulator, interception: FakeLocationInterception(), files: FakeGPXFileReading(),
            scheduler: scheduler, routes: [Route(id: "test", name: "Test", fixes: fixes)]
        )
        let sut = DebugDrawerPluginTransport.direct(to: model)
        let expectedCalls: [FakeLocationOverride.Call] = [
            .deliverRoute(LocationCoordinate(latitude: 1, longitude: 1)), .endRoute, .setEnabled(false)
        ]

        sut.send(LocationCommand(.play))
        sut.send(LocationCommand(.setEnabled(false)))
        scheduler.advance(by: 10)

        #expect(simulator.calls == expectedCalls)
        #expect(sut.snapshot.playback == .stopped)
        #expect(scheduler.pendingCount == 0)
    }

    @Test("Choosing a route and a speed reach the player: the route chosen plays at that speed")
    func routeAndSpeed() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let first = GPXTrack(points: [GPXTrackPoint(latitude: 1, longitude: 1, elevation: nil, time: nil)]).fixes
        let second = GPXTrack(points: [
            GPXTrackPoint(latitude: 5, longitude: 5, elevation: nil, time: start),
            GPXTrackPoint(latitude: 6, longitude: 6, elevation: nil, time: start.addingTimeInterval(20))
        ]).fixes
        let simulator = FakeLocationOverride(isEnabled: true)
        let scheduler = ManualPlaybackScheduler(now: start)
        let model = LocationModel(
            simulator: simulator, interception: FakeLocationInterception(), files: FakeGPXFileReading(),
            scheduler: scheduler, routes: [Route(id: "a", name: "A", fixes: first), Route(id: "b", name: "B", fixes: second)]
        )
        let sut = DebugDrawerPluginTransport.direct(to: model)
        let expectedCalls: [FakeLocationOverride.Call] = [
            .deliverRoute(LocationCoordinate(latitude: 5, longitude: 5)),
            .deliverRoute(LocationCoordinate(latitude: 6, longitude: 6))
        ]

        sut.send(LocationCommand(.selectRoute("b")))
        sut.send(LocationCommand(.setSpeed(.times2)))
        sut.send(LocationCommand(.play))
        scheduler.advance(by: 10)

        #expect(sut.snapshot.routeID == "b")
        #expect(sut.snapshot.speed == .times2)
        #expect(simulator.calls == expectedCalls)
        #expect(sut.snapshot.playback == .finished)
    }

    @Test("Importing a GPX file adds its route and chooses it; one that can't be read is kept as the failure")
    func importingAFile() {
        let good = URL(fileURLWithPath: "/tmp/Morning Drive.gpx")
        let bad = URL(fileURLWithPath: "/tmp/notes.xml")
        let track = GPXTrack(points: [GPXTrackPoint(latitude: 7, longitude: 7, elevation: nil, time: nil)])
        let files = FakeGPXFileReading(files: [good: .success(track), bad: .failure(.notGPX)])
        let model = LocationModel(
            simulator: FakeLocationOverride(isEnabled: true), interception: FakeLocationInterception(), files: files,
            scheduler: ManualPlaybackScheduler(now: Date(timeIntervalSince1970: 0))
        )
        let sut = DebugDrawerPluginTransport.direct(to: model)
        let expectedNames = ["Apple Park Loop", "Golden Gate Bridge", "Morning Drive"]

        sut.send(LocationCommand(.importRoute(bad)))
        let failed = sut.snapshot
        sut.send(LocationCommand(.importRoute(good)))
        let actual = sut.snapshot

        #expect(files.reads == [bad, good])
        #expect(failed.importFailure == .notGPX)
        #expect(failed.routeID == "sample:Apple Park Loop")
        #expect(actual.importFailure == nil)
        #expect(actual.routes.map(\.name) == expectedNames)
        #expect(actual.routeID == "imported:Morning Drive.gpx")
    }

    @Test("Commands take effect in the order sent")
    func commandOrder() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let fixes = GPXTrack(points: [
            GPXTrackPoint(latitude: 1, longitude: 1, elevation: nil, time: start),
            GPXTrackPoint(latitude: 2, longitude: 2, elevation: nil, time: start.addingTimeInterval(10))
        ]).fixes
        let simulator = FakeLocationOverride()
        let model = LocationModel(
            simulator: simulator, interception: FakeLocationInterception(), files: FakeGPXFileReading(),
            scheduler: ManualPlaybackScheduler(now: start), routes: [Route(id: "test", name: "Test", fixes: fixes)]
        )
        let sut = DebugDrawerPluginTransport.direct(to: model)
        let london = LocationSimulator.PresetLocation(name: "London, UK", latitude: 51.5099, longitude: -0.1337)
        let expectedCalls: [FakeLocationOverride.Call] = [
            .setEnabled(true),
            .setCoordinate(LocationCoordinate(latitude: 51.5099, longitude: -0.1337)),
            .setCoordinate(LocationCoordinate(latitude: 40, longitude: -0.1337)),
            .deliverRoute(LocationCoordinate(latitude: 1, longitude: 1)),
            .endRoute,
            .setCoordinate(nil),
            .setEnabled(false)
        ]

        for action: LocationCommand.Action in [
            .setEnabled(true), .choosePreset(london), .setLatitudeText("40"), .play, .stop, .setCoordinate(nil), .setEnabled(false)
        ] {
            sut.send(LocationCommand(action))
        }

        #expect(simulator.calls == expectedCalls)
    }

    @Test("Each drawer's install and uninstall reach the interception once, and one that never installed none; the last uninstall stops the route")
    func installCounting() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let fixes = GPXTrack(points: [
            GPXTrackPoint(latitude: 1, longitude: 1, elevation: nil, time: start),
            GPXTrackPoint(latitude: 2, longitude: 2, elevation: nil, time: start.addingTimeInterval(10))
        ]).fixes
        let simulator = FakeLocationOverride(isEnabled: true, coordinate: CLLocationCoordinate2D(latitude: 3, longitude: 4))
        let interception = FakeLocationInterception()
        let sut = LocationModel(
            simulator: simulator, interception: interception, files: FakeGPXFileReading(),
            scheduler: ManualPlaybackScheduler(now: start), routes: [Route(id: "test", name: "Test", fixes: fixes)]
        )
        // Stand-ins for three drawers: the model counts drawers by identity only.
        let first = NSObject()
        let second = NSObject()
        let never = NSObject()
        let expectedCalls: [FakeLocationOverride.Call] = [
            .deliverRoute(LocationCoordinate(latitude: 1, longitude: 1)), .endRoute
        ]
        let expectedDrawers = [ObjectIdentifier(first), ObjectIdentifier(second)]

        sut.install(in: ObjectIdentifier(first))
        sut.install(in: ObjectIdentifier(second))
        sut.perform(LocationCommand(.play))
        sut.uninstall(from: ObjectIdentifier(never))
        sut.uninstall(from: ObjectIdentifier(first))
        let afterFirst = (sut.snapshot.playback, interception.uninstalled)
        sut.uninstall(from: ObjectIdentifier(second))
        sut.uninstall(from: ObjectIdentifier(second))

        #expect(interception.installed == expectedDrawers)
        #expect(afterFirst.0 == .playing(delivered: 1))
        #expect(afterFirst.1 == [ObjectIdentifier(first)])
        #expect(interception.uninstalled == expectedDrawers)
        #expect(simulator.calls == expectedCalls)
        #expect(sut.snapshot.playback == .stopped)
        #expect(sut.snapshot.isEnabled)
        #expect(sut.snapshot.coordinate == LocationCoordinate(latitude: 3, longitude: 4))
    }

    @Test("A plugin given a model installs and uninstalls that model, in each drawer it is registered in")
    func pluginInstallsItsModel() throws {
        let interception = FakeLocationInterception()
        let model = LocationModel(
            simulator: FakeLocationOverride(), interception: interception, files: FakeGPXFileReading(),
            scheduler: ManualPlaybackScheduler(now: Date(timeIntervalSince1970: 0))
        )
        let firstSuite = temporarySuiteName("LocationModelTests")
        let secondSuite = temporarySuiteName("LocationModelTests")
        let first = DebugDrawer(defaults: try #require(UserDefaults(suiteName: firstSuite)))
        let second = DebugDrawer(defaults: try #require(UserDefaults(suiteName: secondSuite)))
        defer {
            UserDefaults().removePersistentDomain(forName: firstSuite)
            UserDefaults().removePersistentDomain(forName: secondSuite)
        }
        let sut = LocationPlugin(model: model)

        first.registerGlobal(sut)
        second.registerGlobal(sut)
        first.unregisterGlobal(id: sut.id)
        let afterFirst = interception.uninstalled
        second.unregisterGlobal(id: sut.id)

        #expect(interception.installed == [ObjectIdentifier(first), ObjectIdentifier(second)])
        #expect(afterFirst == [ObjectIdentifier(first)])
        #expect(interception.uninstalled == [ObjectIdentifier(first), ObjectIdentifier(second)])
    }
}
