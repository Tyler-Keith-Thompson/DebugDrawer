// Exit tests start a child process, which only the Mac's test runs can do. Installing swaps
// CLLocationManager's methods for the whole process, and uninstalling puts them back, so it runs
// only in a child.
#if os(macOS) && DEBUG
    import CoreLocation
    @testable import DebugDrawer
    @testable import DebugDrawerLocationPlugin
    import DebugDrawerTestSupport
    import Foundation
    import ObjectiveC
    import Testing

    /// A getter other code swaps in on top of the plugin's, which calls whatever it replaced.
    extension CLLocationManager {
        @objc fileprivate func onTopLocation() -> CLLocation? {
            onTopLocation()
        }
    }

    extension LocationSwizzleExitTests {
        @Suite
        struct Uninstall {
            @Test("Removing the plugin puts back each original CLLocationManager method, and managers report Core Location's location again")
            func uninstallRestoresOriginals() async {
                // The children get a home folder of their own, so the files they keep in Application Support and
                // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
                let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
                defer { try? FileManager.default.removeItem(atPath: home) }

                await #expect(processExitsWith: .success) { [home = home as String] in
                    setenv("CFFIXED_USER_HOME", home, 1)
                    guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                    try await Self.uninstallThenReinstall()
                }
            }

            @Test("A method other code swapped in on top stays, and calls Core Location straight through until a reinstall")
            func swizzleOnTopIsLeftInPlace() async {
                // The children get a home folder of their own, so the files they keep in Application Support and
                // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
                let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
                defer { try? FileManager.default.removeItem(atPath: home) }

                await #expect(processExitsWith: .success) { [home = home as String] in
                    setenv("CFFIXED_USER_HOME", home, 1)
                    guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                    try await Self.leaveInPlace()
                }
            }

            /// The implementations of the four methods the plugin swaps, then of the four it swaps
            /// them with.
            @MainActor
            private static func implementations() throws -> [IMP] {
                let selectors = [
                    #selector(CLLocationManager.startUpdatingLocation),
                    #selector(CLLocationManager.stopUpdatingLocation),
                    #selector(CLLocationManager.requestLocation),
                    #selector(getter: CLLocationManager.location),
                    #selector(CLLocationManager.debugDrawerStartUpdatingLocation),
                    #selector(CLLocationManager.debugDrawerStopUpdatingLocation),
                    #selector(CLLocationManager.debugDrawerRequestLocation),
                    #selector(CLLocationManager.debugDrawerLocation)
                ]
                return try selectors.map { try method_getImplementation(#require(class_getInstanceMethod(CLLocationManager.self, $0))) }
            }

            /// Spoofing on at a coordinate, in the child's own argument domain, which the plugin's
            /// defaults read through.
            private static func spoof() {
                UserDefaults.standard.setVolatileDomain(
                    [
                        "com.debugdrawer.location.enabled": true,
                        "com.debugdrawer.location.latitude": 48.8566,
                        "com.debugdrawer.location.longitude": 2.3522
                    ],
                    forName: UserDefaults.argumentDomain
                )
            }

            @MainActor
            private static func uninstallThenReinstall() async throws {
                spoof()
                let suite = temporarySuiteName("LocationUninstallExitTests")
                let defaults = try #require(UserDefaults(suiteName: suite))
                defer { defaults.removePersistentDomain(forName: suite) }
                let drawer = DebugDrawer(defaults: defaults)
                let manager = CLLocationManager()
                let expected = try implementations()

                drawer.installLocation()
                let whileInstalled = try implementations()
                let spoofedWhileInstalled = manager.location?.coordinate.latitude
                drawer.unregisterGlobal(id: LocationPlugin().id)
                let actual = try implementations()
                let afterUninstall = manager.location?.coordinate.latitude
                drawer.unregisterGlobal(id: LocationPlugin().id)
                let afterSecondUninstall = try implementations()
                drawer.installLocation()
                let spoofedReinstalled = manager.location?.coordinate.latitude
                drawer.unregisterGlobal(id: LocationPlugin().id)
                let afterLastUninstall = try implementations()

                #expect(zip(whileInstalled, expected).allSatisfy { $0 != $1 })
                #expect(spoofedWhileInstalled == 48.8566)
                #expect(actual == expected)
                #expect(!drawer.globalPlugins.contains { $0.id == LocationPlugin().id })
                #expect(afterUninstall != 48.8566)
                #expect(afterSecondUninstall == expected)
                #expect(spoofedReinstalled == 48.8566)
                #expect(afterLastUninstall == expected)
            }

            @MainActor
            private static func leaveInPlace() async throws {
                spoof()
                let suite = temporarySuiteName("LocationUninstallExitTests")
                let defaults = try #require(UserDefaults(suiteName: suite))
                defer { defaults.removePersistentDomain(forName: suite) }
                let drawer = DebugDrawer(defaults: defaults)
                let manager = CLLocationManager()
                drawer.installLocation()
                let getter = try #require(class_getInstanceMethod(CLLocationManager.self, #selector(getter: CLLocationManager.location)))
                try method_exchangeImplementations(
                    getter, #require(class_getInstanceMethod(CLLocationManager.self, #selector(CLLocationManager.onTopLocation)))
                )
                let expected = method_getImplementation(getter)

                drawer.unregisterGlobal(id: LocationPlugin().id)
                let actual = method_getImplementation(getter)
                let whileLeftInPlace = manager.location?.coordinate.latitude
                drawer.installLocation()
                let reinstalled = manager.location?.coordinate.latitude
                drawer.unregisterGlobal(id: LocationPlugin().id)

                #expect(actual == expected)
                #expect(whileLeftInPlace != 48.8566)
                #expect(reinstalled == 48.8566)
            }
        }
    }
#endif
