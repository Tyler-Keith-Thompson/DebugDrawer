// Exit tests start a child process, which only the Mac's test runs can do. installLocation swaps
// CLLocationManager's methods for the whole process, so it runs only in a child.
#if os(macOS) && DEBUG
    import CoreLocation
    import DebugDrawer
    @testable import DebugDrawerLocationPlugin
    import Foundation
    import Testing

    extension LocationSwizzleExitTests {
        @Suite
        struct EarlierManager {
            @Test("A manager the app made before any location was simulated gets each simulated point through its own calls, until it stops")
            func managerMadeBeforeSpoofing() async {
                await #expect(processExitsWith: .success) {
                    try await Self.spoofAnEarlierManager()
                }
            }

            @MainActor
            private static func spoofAnEarlierManager() async throws {
                // Spoofing on with no coordinate, in the argument domain: it is the child's own,
                // where the app's domain on disk is shared with every other run of this test
                // binary. The points then come as a route's, which the simulator keeps in memory.
                UserDefaults.standard.setVolatileDomain(
                    ["com.debugdrawer.location.enabled": true],
                    forName: UserDefaults.argumentDomain
                )
                DebugDrawer.shared.installLocation()
                let manager = CLLocationManager()
                let delegate = RecordingLocationDelegate()
                manager.delegate = delegate
                var updates = delegate.updates.makeAsyncIterator()
                let expectedLatitudes: [Double] = [37.3349, 37.3349, 40.7128]

                LocationSimulator.shared.deliverRoute(CLLocation(latitude: 37.3349, longitude: -122.009))
                // Fails at once rather than waiting on a fix Core Location would have to give.
                try #require(LocationSimulator.shared.simulatedLocation != nil)
                // Through the swizzled method, as the app calls it.
                manager.startUpdatingLocation()
                _ = await updates.next()
                let afterStart = manager.location?.coordinate.latitude
                manager.requestLocation()
                _ = await updates.next()
                LocationSimulator.shared.deliverRoute(CLLocation(latitude: 40.7128, longitude: -74.006))
                // Core Location's own stopUpdatingLocation runs too, which is harmless on a manager
                // it never started.
                manager.stopUpdatingLocation()
                LocationSimulator.shared.deliverRoute(CLLocation(latitude: 51.5, longitude: -0.12))

                #expect(afterStart == 37.3349)
                #expect(delegate.locations.map(\.coordinate.latitude) == expectedLatitudes)
            }
        }
    }
#endif
