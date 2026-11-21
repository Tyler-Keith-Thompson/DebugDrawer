import CoreLocation
@testable import DebugDrawerLocationPlugin
import DebugDrawerTestSupport
import Foundation
import Testing

// What the plugin's uninstall asks of the simulator before it puts the swapped methods back. Each
// test drives a LocationSimulator of its own, with the recording service standing in for Core
// Location, so no test starts the Mac's location service.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct LocationReleaseTests {
    @Test("Letting go of the managers starts Core Location again for each one given a simulated location, and keeps the switch and coordinate")
    func releaseHandsManagersBack() throws {
        let suite = temporarySuiteName("LocationReleaseTests")
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = RecordingLocationService()
        let sut = LocationSimulator(defaults: defaults, service: service)
        let first = CLLocationManager()
        let second = CLLocationManager()
        let delegate = RecordingLocationDelegate()
        second.delegate = delegate
        sut.isEnabled = true
        sut.coordinate = CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503)
        sut.startUpdatingLocation(for: first)
        sut.startUpdatingLocation(for: second)
        let expectedCalls: [RecordingLocationService.Call] = [
            .startUpdatingLocation(ObjectIdentifier(first)),
            .startUpdatingLocation(ObjectIdentifier(second))
        ]

        sut.release()
        sut.coordinate = CLLocationCoordinate2D(latitude: 51.5, longitude: -0.12)

        #expect(service.calls == expectedCalls)
        #expect(delegate.locations.isEmpty)
        #expect(sut.isEnabled)
        #expect(sut.coordinate?.latitude == 51.5)
    }

    @Test("Letting go of managers that get real updates starts nothing, and forgets the route's point")
    func releaseWithoutSimulationStartsNothing() throws {
        let suite = temporarySuiteName("LocationReleaseTests")
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = RecordingLocationService()
        let sut = LocationSimulator(defaults: defaults, service: service)
        let manager = CLLocationManager()
        sut.startUpdatingLocation(for: manager)
        let expectedCalls: [RecordingLocationService.Call] = [.startUpdatingLocation(ObjectIdentifier(manager))]

        sut.release()
        sut.isEnabled = true

        #expect(service.calls == expectedCalls)
        #expect(sut.simulatedLocation == nil)
    }
}
