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
                // The children get a home folder of their own, so the files they keep in Application Support and
                // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
                let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
                defer { try? FileManager.default.removeItem(atPath: home) }

                await #expect(processExitsWith: .success) { [home = home as String] in
                    setenv("CFFIXED_USER_HOME", home, 1)
                    guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
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
                let simulator = try #require(LocationSwizzles.simulator)
                let manager = CLLocationManager()
                let delegate = RecordingLocationDelegate()
                manager.delegate = delegate
                var updates = delegate.updates.makeAsyncIterator()
                let expectedLatitudes: [Double] = [37.3349, 37.3349, 40.7128]

                simulator.deliverRoute(CLLocation(latitude: 37.3349, longitude: -122.009))
                // Fails at once rather than waiting on a fix Core Location would have to give.
                try #require(simulator.simulatedLocation != nil)
                // Through the swizzled method, as the app calls it.
                manager.startUpdatingLocation()
                _ = await updates.next()
                let afterStart = manager.location?.coordinate.latitude
                manager.requestLocation()
                _ = await updates.next()
                simulator.deliverRoute(CLLocation(latitude: 40.7128, longitude: -74.006))
                // Core Location's own stopUpdatingLocation runs too, which is harmless on a manager
                // it never started.
                manager.stopUpdatingLocation()
                simulator.deliverRoute(CLLocation(latitude: 51.5, longitude: -0.12))

                #expect(afterStart == 37.3349)
                #expect(delegate.locations.map(\.coordinate.latitude) == expectedLatitudes)
            }
        }
    }
#endif
