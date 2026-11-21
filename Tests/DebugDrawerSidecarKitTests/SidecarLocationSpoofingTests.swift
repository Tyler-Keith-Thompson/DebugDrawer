#if DEBUG && os(macOS)
    import CoreLocation
    import DebugDrawer
    import DebugDrawerLocation
    @testable import DebugDrawerReceiver
    @testable import DebugDrawerSidecarKit
    import Foundation
    import Testing
    import ViewInspector

    // A spoof from the sidecar's button to the production app's receiver: the kit lists the app,
    // shows its spoofing through the Location plugin over the store, and a place's Spoof leaves its
    // coordinate in the store, where the receiver performs it in the session, the host is told and
    // its readings follow. Each wait is for the snapshot that step should produce, never for time.
    @MainActor
    @Suite(.timeLimit(.minutes(1)), .serialized)
    struct SidecarLocationSpoofingTests {
        private let tokyo = LocationCoordinate(latitude: 35.6762, longitude: 139.6503)

        @Test("The kit shows the app's spoofing, and a place's Spoof replaces the host's readings with it in the session")
        func placeSpoofs() async throws {
            let suite = "SidecarLocationSpoofingTests-\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let store = FileManager.default.temporaryDirectory
                .appending(path: "SidecarLocationSpoofingTests-\(UUID().uuidString)")
                .appending(path: "DebugDrawer")
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            var told: [LocationCoordinate?] = []
            let model = LocationSpoofing(sessions: sessions, defaults: defaults) { told.append($0.map { LocationCoordinate($0.coordinate) }) }
            let receiver = DebugDrawerReceiver(directory: store, sessions: sessions)
            receiver.identity = AppPresence.Identity(bundleIdentifier: "com.example.shop", displayName: "Shop", version: "2.4", build: "881")
            receiver.enable(.locationSpoofing(model))
            try receiver.start()
            defer { receiver.stop() }
            sessions.perform(.open(duration: 60))
            let listed = try #require(DebugDrawerSidecarAppList(storeDirectory: store).apps.first)
            let sut = try DebugDrawerSidecarConnection(app: listed)
            defer { sut.close() }
            let hosted = try await sut.host(.locationSpoofing)

            try hosted.body.inspect().find(viewWithAccessibilityIdentifier: "LocationSpoofingPlace-Tokyo, Japan").find(button: "Spoof").tap()

            for await snapshot in model.$snapshot.values where snapshot.isSpoofing {
                break
            }
            let real = CLLocation(latitude: 37.3349, longitude: -122.009)
            #expect(listed.serves(LocationSpoofing.pluginID))
            #expect(told == [tokyo])
            #expect(model.locations(replacing: [real]).map { LocationCoordinate($0.coordinate) } == [tokyo])
            #expect(sessions.auditLog.last?.event == .commandApplied)
        }

        @Test("While spoofed the view shows the coordinate, marks its place, and Stop Spoofing sends stop; another place sends its coordinate")
        func viewWhileSpoofed() throws {
            var sent: [LocationSpoofing.Command] = []
            let sut = LocationSpoofingView(snapshot: LocationSpoofing.Snapshot(coordinate: tokyo)) { sent.append($0) }
            let london = LocationCoordinate(latitude: 51.5099, longitude: -0.1337)

            try sut.inspect().find(button: "Stop Spoofing").tap()
            try sut.inspect().find(viewWithAccessibilityIdentifier: "LocationSpoofingPlace-London, UK").find(button: "Spoof").tap()

            #expect(sent == [.stop, .spoof(london)])
            #expect(throws: Never.self) { try sut.inspect().find(text: "35.6762, 139.6503") }
            #expect(throws: Never.self) {
                try sut.inspect().find(viewWithAccessibilityIdentifier: "LocationSpoofingPlace-Tokyo, Japan").find(text: "Spoofed")
            }
            #expect(throws: (any Error).self) {
                try sut.inspect().find(viewWithAccessibilityIdentifier: "LocationSpoofingPlace-Tokyo, Japan").find(button: "Spoof")
            }
        }

        @Test("The plugin flags the risk, says the location is real, offers no Stop Spoofing, and Spoof is off with empty fields")
        func riskWarningAndRealLocation() throws {
            let sut = LocationSpoofingView(snapshot: LocationSpoofing.Snapshot(coordinate: nil)) { _ in }

            let warning = try sut.inspect().find(viewWithAccessibilityIdentifier: "LocationSpoofingRiskWarning")
            let typedSpoof = try sut.inspect().find(viewWithAccessibilityIdentifier: "LocationSpoofingCoordinate").find(button: "Spoof")

            #expect(throws: Never.self) { try warning.find(ViewType.Text.self, where: { try $0.string().contains("until the session ends") }) }
            #expect(throws: Never.self) { try sut.inspect().find(text: "High Risk") }
            #expect(throws: Never.self) { try sut.inspect().find(text: "No: the app reads the real location") }
            #expect(throws: (any Error).self) { try sut.inspect().find(button: "Stop Spoofing") }
            #expect(typedSpoof.isDisabled())
        }

        @Test("The fields give a coordinate only for two numbers on the Earth, spaces around them ignored")
        func typedCoordinate() {
            let accepted = [
                LocationCoordinate(latitudeText: " 48.8566 ", longitudeText: "2.3522"),
                LocationCoordinate(latitudeText: "-90", longitudeText: "180")
            ]
            let refused = [
                LocationCoordinate(latitudeText: "", longitudeText: "2"),
                LocationCoordinate(latitudeText: "north", longitudeText: "2"),
                LocationCoordinate(latitudeText: "90.1", longitudeText: "0"),
                LocationCoordinate(latitudeText: "0", longitudeText: "-180.1"),
                LocationCoordinate(latitudeText: "nan", longitudeText: "0")
            ]

            #expect(accepted == [LocationCoordinate(latitude: 48.8566, longitude: 2.3522), LocationCoordinate(latitude: -90, longitude: 180)])
            #expect(refused.allSatisfy { $0 == nil })
        }

        @Test("The shipped Location plugin is served under the capability's ID")
        func shippedPlugin() {
            let sut = DebugDrawerSidecarPlugin.locationSpoofing

            #expect([sut.id, sut.title, sut.icon] == [LocationSpoofing.pluginID, "Location", "location.circle"])
        }
    }
#endif
