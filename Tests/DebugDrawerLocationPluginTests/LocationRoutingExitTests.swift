// Exit tests start a child process, which only the Mac's test runs can do. installLocation swaps
// CLLocationManager's methods for the whole process, so it runs only in a child. Each drawer here
// keeps its switch and coordinate in a suite of its own; nothing is set in the argument domain,
// which every suite reads first and would hide them.
#if os(macOS) && DEBUG
    import CoreLocation
    @testable import DebugDrawer
    @testable import DebugDrawerLocationPlugin
    import DebugDrawerTestSupport
    import Foundation
    import Testing

    extension LocationSwizzleExitTests {
        @Suite
        struct Routing {
            @Test("A drawer of its own simulates for the app's managers and leaves DebugDrawer.shared's model and defaults alone")
            func ownDrawerLeavesSharedAlone() async {
                // The children get a home folder of their own, so the files they keep in Application Support and
                // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
                let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
                defer { try? FileManager.default.removeItem(atPath: home) }

                await #expect(processExitsWith: .success) { [home = home as String] in
                    setenv("CFFIXED_USER_HOME", home, 1)
                    guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                    try await Self.ownDrawer()
                }
            }

            @Test("Two drawers of their own: an updating manager gets the later one's location, and the earlier one's once the later removes it")
            func latestInstallGetsTheManagers() async {
                // The children get a home folder of their own, so the files they keep in Application Support and
                // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
                let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
                defer { try? FileManager.default.removeItem(atPath: home) }

                await #expect(processExitsWith: .success) { [home = home as String] in
                    setenv("CFFIXED_USER_HOME", home, 1)
                    guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                    try await Self.twoDrawers()
                }
            }

            /// The shared drawer's switch and coordinate, as its defaults hold them.
            private static func sharedDefaults() -> [Double?] {
                [
                    UserDefaults.debugDrawer.object(forKey: _LocationSpoofingStore.enabledKey) as? Double,
                    UserDefaults.debugDrawer.object(forKey: _LocationSpoofingStore.latitudeKey) as? Double,
                    UserDefaults.debugDrawer.object(forKey: _LocationSpoofingStore.longitudeKey) as? Double
                ]
            }

            @MainActor
            private static func ownDrawer() async throws {
                let suite = temporarySuiteName("LocationRoutingExitTests")
                let defaults = try #require(UserDefaults(suiteName: suite))
                defer { defaults.removePersistentDomain(forName: suite) }
                DebugDrawer.shared.installLocation()
                let drawer = DebugDrawer(defaults: defaults)
                drawer.installLocation()
                // The model installLocation made for the drawer; the closure isn't called again.
                let model = drawer.installerState { LocationModel(defaults: defaults) }
                let manager = CLLocationManager()
                let sharedSnapshot = LocationModel.shared.snapshot
                let sharedKept = sharedDefaults()
                let expected = 48.8566

                model.perform(LocationCommand(.setEnabled(true)))
                model.perform(LocationCommand(.setCoordinate(LocationCoordinate(latitude: expected, longitude: 2.3522))))
                let whileInstalled = manager.location?.coordinate.latitude
                let sharedWhileInstalled = LocationModel.shared.snapshot
                let sharedKeptWhileInstalled = sharedDefaults()
                drawer.unregisterGlobal(id: LocationPlugin().id)
                let afterRemoval = manager.location?.coordinate.latitude

                #expect(model !== LocationModel.shared)
                #expect(whileInstalled == expected)
                #expect(model.snapshot.active == LocationCoordinate(latitude: expected, longitude: 2.3522))
                #expect(defaults.bool(forKey: _LocationSpoofingStore.enabledKey))
                #expect(defaults.double(forKey: _LocationSpoofingStore.latitudeKey) == expected)
                #expect(sharedWhileInstalled == sharedSnapshot)
                #expect(sharedKeptWhileInstalled == sharedKept)
                #expect(sharedWhileInstalled.active?.latitude != expected)
                #expect(afterRemoval != expected)
                #expect(LocationSwizzles.simulator != nil)
            }

            @MainActor
            private static func twoDrawers() async throws {
                let firstSuite = temporarySuiteName("LocationRoutingExitTests")
                let secondSuite = temporarySuiteName("LocationRoutingExitTests")
                let firstDefaults = try #require(UserDefaults(suiteName: firstSuite))
                let secondDefaults = try #require(UserDefaults(suiteName: secondSuite))
                defer {
                    firstDefaults.removePersistentDomain(forName: firstSuite)
                    secondDefaults.removePersistentDomain(forName: secondSuite)
                }
                // Both spoof before they install, so no manager is ever handed to Core Location,
                // which could ask the person running the tests for location access.
                for (defaults, latitude, longitude) in [(firstDefaults, 48.8566, 2.3522), (secondDefaults, 35.6762, 139.6503)] {
                    defaults.set(true, forKey: _LocationSpoofingStore.enabledKey)
                    defaults.set(latitude, forKey: _LocationSpoofingStore.latitudeKey)
                    defaults.set(longitude, forKey: _LocationSpoofingStore.longitudeKey)
                }
                let first = DebugDrawer(defaults: firstDefaults)
                let second = DebugDrawer(defaults: secondDefaults)
                first.installLocation()
                let manager = CLLocationManager()
                let delegate = RecordingLocationDelegate()
                manager.delegate = delegate
                var updates = delegate.updates.makeAsyncIterator()
                let expectedLatitudes = [48.8566, 35.6762, 48.8566]

                manager.startUpdatingLocation()
                _ = await updates.next()
                second.installLocation()
                let whileSecond = manager.location?.coordinate.latitude
                second.unregisterGlobal(id: LocationPlugin().id)
                let afterSecond = manager.location?.coordinate.latitude
                manager.stopUpdatingLocation()
                first.unregisterGlobal(id: LocationPlugin().id)

                #expect(delegate.locations.map(\.coordinate.latitude) == expectedLatitudes)
                #expect(whileSecond == 35.6762)
                #expect(afterSecond == 48.8566)
                #expect(LocationSwizzles.simulator == nil)
            }
        }
    }
#endif
