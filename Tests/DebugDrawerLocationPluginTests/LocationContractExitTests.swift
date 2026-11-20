// The interception contract's checks (DebugDrawerInterceptionContract). Exit tests start a child
// process, which only the Mac's test runs can do; installing swaps CLLocationManager's methods for
// the whole process, so each check runs in a child of its own, which keeps its spoofing state in
// its own argument domain.
//
// Two checks are left out. checkCapturesNothingUninstalled starts a manager's updates with the
// plugin removed, which reaches Core Location and could ask the person running the tests for
// location access. checkLeavesOutDrawerActivity has nothing to check: the drawer never starts
// location updates of its own (the Permissions plugin only reads the authorization status).
#if os(macOS) && DEBUG
    import CoreLocation
    @testable import DebugDrawer
    import DebugDrawerInterceptionContract
    @testable import DebugDrawerLocationPlugin
    import Foundation
    import ObjectiveC
    import Testing

    /// A manager that carries the marker of the call that started it.
    private final class MarkedLocationManager: CLLocationManager {
        let marker: String

        init(marker: String) {
            self.marker = marker
            super.init()
        }
    }

    /// The Location plugin's side of the contract. What it keeps of the app's is the managers
    /// updating their location; a captured call starts a manager's updates while a location is
    /// simulated, so Core Location is never asked, and the app's call reads a manager's location
    /// with spoofing off.
    @MainActor
    private final class LocationContract: UnchangedResultContract, CaptureContract {
        /// What the app's manager reports.
        struct AppResult: Equatable {
            var latitude: CLLocationDegrees?
            var longitude: CLLocationDegrees?
        }

        /// The managers the app still holds, newest last: at most `kept` of them.
        private var managers: [MarkedLocationManager] = []
        private var kept = Int.max

        /// A contract whose child has spoofing on at a coordinate, or off.
        init(spoofing: Bool) {
            UserDefaults.standard.setVolatileDomain(
                [
                    "com.debugdrawer.location.enabled": spoofing,
                    "com.debugdrawer.location.latitude": 48.8566,
                    "com.debugdrawer.location.longitude": 2.3522
                ],
                forName: UserDefaults.argumentDomain
            )
        }

        func install(in drawer: DebugDrawer) {
            drawer.installLocation()
        }

        func uninstall(from drawer: DebugDrawer) {
            drawer.unregisterGlobal(id: LocationPlugin().id)
        }

        /// The implementations of the four methods the plugin swaps, then of the four it swaps
        /// them with.
        func processState() throws -> [IMP] {
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

        func makeAppCall() async throws -> AppResult {
            let location = CLLocationManager().location
            return AppResult(latitude: location?.coordinate.latitude, longitude: location?.coordinate.longitude)
        }

        /// Keeps only the newest `count` managers alive, as an app that lets go of the others.
        func limitCapture(to count: Int) {
            kept = count
            managers = Array(managers.suffix(count))
        }

        func makeCapturedCall(_ marker: String) async throws {
            let manager = MarkedLocationManager(marker: marker)
            managers.append(manager)
            managers = Array(managers.suffix(kept))
            manager.startUpdatingLocation()
        }

        func capturedMarkers(through marker: String) async throws -> [String] {
            // Tracked as startUpdatingLocation returns, so there is nothing to wait for. The
            // simulator the swizzled methods ask: the latest drawer's, which the earlier drawers'
            // managers were handed to.
            (LocationSwizzles.simulator?.updatingManagers() ?? []).compactMap { ($0 as? MarkedLocationManager)?.marker }
        }

        func capturedCount() -> Int {
            LocationSwizzles.simulator?.updatingManagers().count ?? 0
        }
    }

    @Suite("The Location plugin keeps the interception contract, in a child process", .timeLimit(.minutes(1)))
    struct LocationContractExitTests {
        @Test("Installing the Location plugin twice, or in a second drawer, changes the process as installing it once does")
        func idempotentInstall() async {
            await #expect(processExitsWith: .success) {
                try await LocationContract(spoofing: false).checkIdempotentInstall()
            }
        }

        @Test("A manager that starts updating is tracked once with the Location plugin installed twice")
        func capturesOnceInstalledTwice() async {
            await #expect(processExitsWith: .success) {
                try await LocationContract(spoofing: true).checkCapturesOnceInstalledTwice()
            }
        }

        @Test("Removing the Location plugin from the last drawer holding it puts back what installing changed")
        func reversibleUninstall() async {
            await #expect(processExitsWith: .success) {
                try await LocationContract(spoofing: false).checkReversibleUninstall()
            }
        }

        @Test("With spoofing off, a manager reports the same location with the Location plugin installed as without")
        func unchangedResult() async {
            await #expect(processExitsWith: .success) {
                try await LocationContract(spoofing: false).checkUnchangedResult()
            }
        }

        @Test("The Location plugin holds no more updating managers than the app keeps alive")
        func boundedCapture() async {
            await #expect(processExitsWith: .success) {
                try await LocationContract(spoofing: true).checkBoundedCapture()
            }
        }
    }
#endif
