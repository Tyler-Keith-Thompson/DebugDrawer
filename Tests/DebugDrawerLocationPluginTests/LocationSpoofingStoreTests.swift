@testable import DebugDrawerLocationPlugin
import DebugDrawerTestSupport
import Foundation
import Testing

// Each test keeps the switch and coordinate in a defaults suite of its own, removed afterward.
@Suite
struct LocationSpoofingStoreTests {
    @Test("Nothing kept reads as spoofing off with no coordinate")
    func emptyDefaults() throws {
        let suite = temporarySuiteName("LocationSpoofingStoreTests")
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let sut = _LocationSpoofingStore(defaults: defaults)

        #expect(!sut.isEnabled)
        #expect(sut.coordinate == nil)
    }

    @Test("The switch and coordinate are kept under the keys earlier versions used, and read back")
    func keysAndReadBack() throws {
        let suite = temporarySuiteName("LocationSpoofingStoreTests")
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let sut = _LocationSpoofingStore(defaults: defaults)
        let expected = LocationCoordinate(latitude: -33.8634, longitude: 151.211)

        sut.isEnabled = true
        sut.coordinate = expected

        #expect(defaults.bool(forKey: "com.debugdrawer.location.enabled"))
        #expect(defaults.double(forKey: "com.debugdrawer.location.latitude") == -33.8634)
        #expect(defaults.double(forKey: "com.debugdrawer.location.longitude") == 151.211)
        #expect(sut.isEnabled)
        #expect(_LocationSpoofingStore(defaults: defaults).coordinate == expected)
    }

    @Test("No coordinate removes both keys")
    func clearingRemovesKeys() throws {
        let suite = temporarySuiteName("LocationSpoofingStoreTests")
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let sut = _LocationSpoofingStore(defaults: defaults)
        sut.coordinate = LocationCoordinate(latitude: 1, longitude: 2)

        sut.coordinate = nil

        #expect(defaults.object(forKey: "com.debugdrawer.location.latitude") == nil)
        #expect(defaults.object(forKey: "com.debugdrawer.location.longitude") == nil)
        #expect(sut.coordinate == nil)
    }

    @Test("A latitude kept without a longitude is no coordinate")
    func halfACoordinate() throws {
        let suite = temporarySuiteName("LocationSpoofingStoreTests")
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(12.5, forKey: "com.debugdrawer.location.latitude")

        let sut = _LocationSpoofingStore(defaults: defaults)

        #expect(sut.coordinate == nil)
    }
}
