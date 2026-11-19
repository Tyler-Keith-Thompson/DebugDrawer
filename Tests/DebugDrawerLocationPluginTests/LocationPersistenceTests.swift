import CoreLocation
import DebugDrawer
@testable import DebugDrawerLocationPlugin
import Foundation
import Testing

// Each test drives a LocationModel over a real LocationSimulator whose seams are fakes: the
// switch and coordinate are kept in a FakeLocationSpoofingStore, the recording service stands in
// for Core Location, and nothing swaps CLLocationManager's methods. A second model over a second
// simulator on the same store is the next launch.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct LocationPersistenceTests {
    @Test("The switch and the coordinate a model sets are kept, and the next launch's model reads them back into its fields")
    func keptAcrossLaunches() throws {
        let store = FakeLocationSpoofingStore()
        let model = LocationModel(
            simulator: LocationSimulator(store: store, service: RecordingLocationService()), interception: FakeLocationInterception(),
            files: FakeGPXFileReading(), scheduler: ManualPlaybackScheduler(now: Date(timeIntervalSince1970: 0))
        )
        let london = try #require(model.snapshot.presets.first { $0.name == "London, UK" })
        let expected = LocationCoordinate(latitude: 51.5099, longitude: -0.1337)

        model.perform(LocationCommand(.setEnabled(true)))
        model.perform(LocationCommand(.choosePreset(london)))
        let sut = LocationModel(
            simulator: LocationSimulator(store: store, service: RecordingLocationService()), interception: FakeLocationInterception(),
            files: FakeGPXFileReading(), scheduler: ManualPlaybackScheduler(now: Date(timeIntervalSince1970: 0))
        )
        let actual = sut.snapshot

        #expect(store.isEnabled)
        #expect(store.coordinate == expected)
        #expect(actual.isEnabled)
        #expect(actual.coordinate == expected)
        #expect(actual.active == expected)
        #expect([actual.latitudeText, actual.longitudeText] == ["51.5099", "-0.1337"])
    }

    @Test("Clearing the coordinate and turning spoofing off are kept too")
    func clearingIsKept() {
        let store = FakeLocationSpoofingStore(isEnabled: true, coordinate: LocationCoordinate(latitude: 10, longitude: 20))
        let sut = LocationModel(
            simulator: LocationSimulator(store: store, service: RecordingLocationService()), interception: FakeLocationInterception(),
            files: FakeGPXFileReading(), scheduler: ManualPlaybackScheduler(now: Date(timeIntervalSince1970: 0))
        )
        let before = sut.snapshot

        sut.perform(LocationCommand(.setCoordinate(nil)))
        sut.perform(LocationCommand(.setEnabled(false)))

        #expect(before.active == LocationCoordinate(latitude: 10, longitude: 20))
        #expect(store.coordinate == nil)
        #expect(!store.isEnabled)
        #expect(sut.snapshot.active == nil)
    }

    @Test("A kept coordinate out of range reads as none, with empty fields")
    func keptOutOfRangeIsNone() {
        let store = FakeLocationSpoofingStore(isEnabled: true, coordinate: LocationCoordinate(latitude: 91, longitude: 0))

        let sut = LocationModel(
            simulator: LocationSimulator(store: store, service: RecordingLocationService()), interception: FakeLocationInterception(),
            files: FakeGPXFileReading(), scheduler: ManualPlaybackScheduler(now: Date(timeIntervalSince1970: 0))
        )

        #expect(sut.snapshot.coordinate == nil)
        #expect(sut.snapshot.active == nil)
        #expect([sut.snapshot.latitudeText, sut.snapshot.longitudeText] == ["", ""])
    }

    @Test("A route's points aren't kept: the next launch's model has the fixed coordinate in effect")
    func routeIsNotKept() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let fixes = GPXTrack(points: [
            GPXTrackPoint(latitude: 1, longitude: 1, elevation: nil, time: start),
            GPXTrackPoint(latitude: 2, longitude: 2, elevation: nil, time: start.addingTimeInterval(10))
        ]).fixes
        let store = FakeLocationSpoofingStore(isEnabled: true, coordinate: LocationCoordinate(latitude: 10, longitude: 20))
        let model = LocationModel(
            simulator: LocationSimulator(store: store, service: RecordingLocationService()), interception: FakeLocationInterception(),
            files: FakeGPXFileReading(), scheduler: ManualPlaybackScheduler(now: start), routes: [Route(id: "test", name: "Test", fixes: fixes)]
        )

        model.perform(LocationCommand(.play))
        let playing = model.snapshot.active
        let sut = LocationModel(
            simulator: LocationSimulator(store: store, service: RecordingLocationService()), interception: FakeLocationInterception(),
            files: FakeGPXFileReading(), scheduler: ManualPlaybackScheduler(now: start)
        )

        #expect(playing == LocationCoordinate(latitude: 1, longitude: 1))
        #expect(sut.snapshot.active == LocationCoordinate(latitude: 10, longitude: 20))
    }
}
