// Exit tests start a child process, which only the Mac's test runs can do.
#if os(macOS) && DEBUG
    import CoreLocation
    @testable import DebugDrawerLocationPlugin
    import Foundation
    import Testing

    // An exit test's body captures nothing, so each bound is a body of its own.
    @Suite(.timeLimit(.minutes(1)))
    struct LocationCoordinateTrapExitTests {
        @Test("Setting a latitude above 90 traps")
        func latitudeAbove() async {
            await #expect(processExitsWith: .failure) {
                let defaults = UserDefaults(suiteName: "LocationCoordinateTrapExitTests") ?? .standard
                let sut = LocationSimulator(defaults: defaults, service: RecordingLocationService())

                sut.coordinate = CLLocationCoordinate2D(latitude: 90.5, longitude: 0)
            }
        }

        @Test("Setting a latitude below -90 traps")
        func latitudeBelow() async {
            await #expect(processExitsWith: .failure) {
                let defaults = UserDefaults(suiteName: "LocationCoordinateTrapExitTests") ?? .standard
                let sut = LocationSimulator(defaults: defaults, service: RecordingLocationService())

                sut.coordinate = CLLocationCoordinate2D(latitude: -91, longitude: 0)
            }
        }

        @Test("Setting a longitude above 180 traps")
        func longitudeAbove() async {
            await #expect(processExitsWith: .failure) {
                let defaults = UserDefaults(suiteName: "LocationCoordinateTrapExitTests") ?? .standard
                let sut = LocationSimulator(defaults: defaults, service: RecordingLocationService())

                sut.coordinate = CLLocationCoordinate2D(latitude: 0, longitude: 180.5)
            }
        }

        @Test("Setting a longitude below -180 traps")
        func longitudeBelow() async {
            await #expect(processExitsWith: .failure) {
                let defaults = UserDefaults(suiteName: "LocationCoordinateTrapExitTests") ?? .standard
                let sut = LocationSimulator(defaults: defaults, service: RecordingLocationService())

                sut.coordinate = CLLocationCoordinate2D(latitude: 0, longitude: -181)
            }
        }
    }
#endif
