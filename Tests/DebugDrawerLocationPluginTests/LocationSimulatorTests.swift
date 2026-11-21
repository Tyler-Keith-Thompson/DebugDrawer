import CoreLocation
@testable import DebugDrawerLocationPlugin
import DebugDrawerTestSupport
import Foundation
import Testing

// Each test drives a LocationSimulator of its own, over defaults of its own, with a real
// CLLocationManager whose calls it makes directly as the swizzled methods would: nothing here swaps
// CLLocationManager's methods, and the recording service stands in for Core Location, so no test
// starts the Mac's location service.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct LocationSimulatorTests {
    @Test("A manager created before spoofing is turned on gets the spoofed location when it starts updating, and Core Location isn't started")
    func managerCreatedBeforeSpoofing() async throws {
        let defaults = try #require(UserDefaults(suiteName: temporarySuiteName("LocationSimulatorTests")))
        let service = RecordingLocationService()
        let sut = LocationSimulator(defaults: defaults, service: service)
        let manager = CLLocationManager()
        let delegate = RecordingLocationDelegate()
        manager.delegate = delegate
        var updates = delegate.updates.makeAsyncIterator()
        let expectedCoordinate: [Double] = [51.5, -0.12]

        sut.isEnabled = true
        sut.coordinate = CLLocationCoordinate2D(latitude: 51.5, longitude: -0.12)
        sut.startUpdatingLocation(for: manager)
        let actual = try #require(await updates.next())

        #expect([actual.coordinate.latitude, actual.coordinate.longitude] == expectedCoordinate)
        #expect(service.calls.isEmpty)
    }

    @Test("A manager already updating when spoofing begins has its real updates stopped and gets the spoofed location")
    func managerUpdatingBeforeSpoofing() throws {
        let defaults = try #require(UserDefaults(suiteName: temporarySuiteName("LocationSimulatorTests")))
        let service = RecordingLocationService()
        let sut = LocationSimulator(defaults: defaults, service: service)
        let manager = CLLocationManager()
        let delegate = RecordingLocationDelegate()
        manager.delegate = delegate
        let expectedCalls: [RecordingLocationService.Call] = [
            .startUpdatingLocation(ObjectIdentifier(manager)),
            .stopUpdatingLocation(ObjectIdentifier(manager))
        ]
        let expectedLatitudes: [Double] = [35.6762]

        sut.startUpdatingLocation(for: manager)
        sut.isEnabled = true
        sut.coordinate = CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503)

        #expect(service.calls == expectedCalls)
        #expect(delegate.locations.map(\.coordinate.latitude) == expectedLatitudes)
    }

    @Test("Turning spoofing off starts Core Location again for each manager still updating, and not for one that stopped")
    func disablingRestoresRealUpdates() throws {
        let defaults = try #require(UserDefaults(suiteName: temporarySuiteName("LocationSimulatorTests")))
        defaults.set(true, forKey: "com.debugdrawer.location.enabled")
        defaults.set(40.7128, forKey: "com.debugdrawer.location.latitude")
        defaults.set(-74.006, forKey: "com.debugdrawer.location.longitude")
        let service = RecordingLocationService()
        let sut = LocationSimulator(defaults: defaults, service: service)
        let updating = CLLocationManager()
        let stopped = CLLocationManager()
        let expectedCalls: [RecordingLocationService.Call] = [
            .stopUpdatingLocation(ObjectIdentifier(stopped)),
            .startUpdatingLocation(ObjectIdentifier(updating))
        ]

        sut.startUpdatingLocation(for: updating)
        sut.startUpdatingLocation(for: stopped)
        sut.stopUpdatingLocation(for: stopped)
        sut.isEnabled = false

        #expect(service.calls == expectedCalls)
        #expect(sut.simulatedLocation == nil)
    }

    @Test("Each new coordinate is delivered to every updating manager, and none to one that stopped")
    func coordinateChangesReachUpdatingManagers() throws {
        let defaults = try #require(UserDefaults(suiteName: temporarySuiteName("LocationSimulatorTests")))
        defaults.set(true, forKey: "com.debugdrawer.location.enabled")
        let sut = LocationSimulator(defaults: defaults, service: RecordingLocationService())
        let first = CLLocationManager()
        let firstDelegate = RecordingLocationDelegate()
        first.delegate = firstDelegate
        let second = CLLocationManager()
        let secondDelegate = RecordingLocationDelegate()
        second.delegate = secondDelegate
        let expectedLatitudes: [Double] = [10, 20]

        sut.startUpdatingLocation(for: first)
        sut.startUpdatingLocation(for: second)
        sut.coordinate = CLLocationCoordinate2D(latitude: 10, longitude: 10)
        sut.coordinate = CLLocationCoordinate2D(latitude: 20, longitude: 20)
        sut.stopUpdatingLocation(for: second)
        sut.coordinate = CLLocationCoordinate2D(latitude: 30, longitude: 30)

        #expect(firstDelegate.locations.map(\.coordinate.latitude) == expectedLatitudes + [30])
        #expect(secondDelegate.locations.map(\.coordinate.latitude) == expectedLatitudes)
    }

    @Test("While spoofing, requestLocation answers once with the spoofed location and location returns it")
    func requestAndLocationWhileSpoofing() async throws {
        let defaults = try #require(UserDefaults(suiteName: temporarySuiteName("LocationSimulatorTests")))
        defaults.set(true, forKey: "com.debugdrawer.location.enabled")
        defaults.set(-33.8634, forKey: "com.debugdrawer.location.latitude")
        defaults.set(151.211, forKey: "com.debugdrawer.location.longitude")
        let service = RecordingLocationService()
        let sut = LocationSimulator(defaults: defaults, service: service)
        let manager = CLLocationManager()
        let delegate = RecordingLocationDelegate()
        manager.delegate = delegate
        var updates = delegate.updates.makeAsyncIterator()
        let expectedLatitude = -33.8634

        sut.requestLocation(for: manager)
        let actual = try #require(await updates.next())

        #expect(actual.coordinate.latitude == expectedLatitude)
        #expect(sut.location(for: manager)?.coordinate.latitude == expectedLatitude)
        #expect(service.calls.isEmpty)
    }

    @Test("Without a spoofed location, requestLocation goes to Core Location and the manager isn't kept as updating")
    func requestWithoutSpoofing() throws {
        let defaults = try #require(UserDefaults(suiteName: temporarySuiteName("LocationSimulatorTests")))
        defaults.set(true, forKey: "com.debugdrawer.location.enabled")
        let service = RecordingLocationService()
        let sut = LocationSimulator(defaults: defaults, service: service)
        let manager = CLLocationManager()
        let expectedCalls: [RecordingLocationService.Call] = [.requestLocation(ObjectIdentifier(manager))]

        sut.requestLocation(for: manager)
        sut.coordinate = CLLocationCoordinate2D(latitude: 1, longitude: 1)

        #expect(service.calls == expectedCalls)
    }

    @Test("Spoofing on with no coordinate set simulates nothing")
    func enabledWithoutCoordinate() throws {
        let defaults = try #require(UserDefaults(suiteName: temporarySuiteName("LocationSimulatorTests")))
        let sut = LocationSimulator(defaults: defaults, service: RecordingLocationService())

        sut.isEnabled = true

        #expect(sut.simulatedLocation == nil)
    }

    @Test("0, 0 is a coordinate like any other, not the absence of one")
    func nullIsland() throws {
        let defaults = try #require(UserDefaults(suiteName: temporarySuiteName("LocationSimulatorTests")))
        let sut = LocationSimulator(defaults: defaults, service: RecordingLocationService())
        let expected: [Double] = [0, 0]

        sut.isEnabled = true
        sut.coordinate = CLLocationCoordinate2D(latitude: 0, longitude: 0)

        let actual = try #require(sut.simulatedLocation)
        #expect([actual.coordinate.latitude, actual.coordinate.longitude] == expected)
    }

    @Test("The range's bounds are coordinates that can be spoofed", arguments: [[90.0, 180.0], [-90, -180]])
    func rangeBounds(bounds: [Double]) throws {
        let defaults = try #require(UserDefaults(suiteName: temporarySuiteName("LocationSimulatorTests")))
        let sut = LocationSimulator(defaults: defaults, service: RecordingLocationService())

        sut.isEnabled = true
        sut.coordinate = CLLocationCoordinate2D(latitude: bounds[0], longitude: bounds[1])

        let actual = try #require(sut.simulatedLocation)
        #expect([actual.coordinate.latitude, actual.coordinate.longitude] == bounds)
    }

    @Test("A kept coordinate out of range is no coordinate")
    func keptCoordinateOutOfRange() throws {
        let defaults = try #require(UserDefaults(suiteName: temporarySuiteName("LocationSimulatorTests")))
        defaults.set(true, forKey: "com.debugdrawer.location.enabled")
        defaults.set(91.0, forKey: "com.debugdrawer.location.latitude")
        defaults.set(0.0, forKey: "com.debugdrawer.location.longitude")

        let sut = LocationSimulator(defaults: defaults, service: RecordingLocationService())

        #expect(sut.coordinate == nil)
        #expect(sut.simulatedLocation == nil)
    }
}
