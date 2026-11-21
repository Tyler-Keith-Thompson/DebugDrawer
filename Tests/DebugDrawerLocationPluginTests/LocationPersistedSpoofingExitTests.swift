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
        struct PersistedSpoofing {
            @Test("Spoofing kept from the last launch is in effect once installLocation runs in a new process")
            func persistedSpoofingAfterRelaunch() async {
                // The children get a home folder of their own, so the files they keep in Application Support and
                // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
                let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
                defer { try? FileManager.default.removeItem(atPath: home) }

                await #expect(processExitsWith: .success) { [home = home as String] in
                    setenv("CFFIXED_USER_HOME", home, 1)
                    guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                    try await Self.relaunch()
                }
            }

            /// The new launch: the previous one left spoofing on at a coordinate in the app's
            /// defaults, and nothing here turns it on.
            @MainActor
            private static func relaunch() async throws {
                // The values the launch finds in the standard defaults, in the argument domain:
                // it is the child's own, where the app's domain on disk is shared with every
                // other run of this test binary.
                UserDefaults.standard.setVolatileDomain([
                    "com.debugdrawer.location.enabled": true,
                    "com.debugdrawer.location.latitude": 48.8584,
                    "com.debugdrawer.location.longitude": 2.2945
                ], forName: UserDefaults.argumentDomain)
                DebugDrawer.shared.installLocation()
                let simulator = try #require(LocationSwizzles.simulator)
                let manager = CLLocationManager()
                let delegate = RecordingLocationDelegate()
                manager.delegate = delegate
                var updates = delegate.updates.makeAsyncIterator()
                let expected: [Double] = [48.8584, 2.2945]
                // Fails at once rather than waiting on a fix Core Location would have to give.
                try #require(simulator.simulatedLocation != nil)

                manager.startUpdatingLocation()
                let actual = await updates.next()

                #expect(actual.map { [$0.coordinate.latitude, $0.coordinate.longitude] } == expected)
                #expect(manager.location.map { [$0.coordinate.latitude, $0.coordinate.longitude] } == expected)
            }
        }
    }
#endif
