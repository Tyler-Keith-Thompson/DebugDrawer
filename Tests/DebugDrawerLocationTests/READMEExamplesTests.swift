// The README's "Location spoofing in production" example, verbatim, so the README cannot drift
// from the code: the app's location signals, spoofing enabled under a grant policy, a spoof left in
// the store by a sidecar whose grant lists the capability, the app's readings and fraud signal
// following it, the indicator, and the real readings back as the session ends.
#if DEBUG
    import CoreLocation
    import CryptoKit
    @testable import DebugDrawerLocation
    @testable import DebugDrawerReceiver
    import Foundation
    import SwiftUI
    import Testing

    /// What the app knows of where the device is: the location its features use, and whether it is
    /// spoofed, which the app's own fraud checks read.
    @MainActor
    final class LocationSignals: ObservableObject {
        @Published private(set) var location: CLLocation?
        @Published private(set) var isSpoofed = false

        /// Told by `LocationSpoofing` as a spoof starts, moves and ends.
        func spoofingDidChange(_ spoofed: CLLocation?) {
            isSpoofed = spoofed != nil
            // At the end, drop the spoofed location until Core Location delivers a real one.
            location = spoofed
        }

        func update(_ location: CLLocation?) {
            self.location = location
        }
    }

    @MainActor
    final class ProductionLocation {
        let sessions: DebugDrawerSessions
        let signals: LocationSignals
        let spoofing: LocationSpoofing
        let receiver: DebugDrawerReceiver

        init(grantServerKey: Curve25519.Signing.PublicKey, container: URL) throws {
            sessions = DebugDrawerSessions(maximumDuration: 15 * 60, grantPolicy: DebugDrawerGrantPolicy(
                verifier: DebugDrawerSignedGrantVerifier(keys: [.ed25519(grantServerKey)]),
                audience: "com.example.MyApp"
            ))
            let signals = LocationSignals()
            self.signals = signals
            spoofing = LocationSpoofing(sessions: sessions, spoofingDidChange: signals.spoofingDidChange)
            receiver = DebugDrawerReceiver(directory: container.appending(path: "DebugDrawer"), sessions: sessions)
            receiver.enable(.locationSpoofing(spoofing))
            try receiver.start()
        }

        /// From the app's CLLocationManagerDelegate, locationManager(_:didUpdateLocations:).
        func didUpdateLocations(_ locations: [CLLocation]) {
            signals.update(spoofing.locations(replacing: locations).last)
        }
    }

    struct LocationSpoofingIndicator: View {
        @ObservedObject var spoofing: LocationSpoofing

        var body: some View {
            if let coordinate = spoofing.snapshot.coordinate {
                Label("Location spoofed: \(coordinate.latitude), \(coordinate.longitude)", systemImage: "location.slash")
            }
        }
    }

    // Run serialized: the README's model keeps its flag in the standard defaults, as an app's does.
    @MainActor
    @Suite(.timeLimit(.minutes(1)), .serialized)
    struct READMEExamplesTests {
        @Test("README: a spoof in a session whose grant lists it replaces the app's readings and flags them, until the session ends")
        func readmeLocationSpoofing() throws {
            let container = FileManager.default.temporaryDirectory.appending(path: "READMELocationSpoofing-\(UUID().uuidString)")
            let serverKey = Curve25519.Signing.PrivateKey()
            let app = try ProductionLocation(grantServerKey: serverKey.publicKey, container: container)
            defer {
                app.receiver.stop()
                UserDefaults.standard.removeObject(forKey: LocationSpoofing.spoofingDefaultsKey)
            }
            let grant = try DebugDrawerTestGrantSigner(key: serverKey).token(for: DebugDrawerGrant(
                id: "g-\(UUID().uuidString)", subject: "jane@example.com", audiences: ["com.example.MyApp"],
                capabilities: [LocationSpoofing.pluginID], notBefore: Date().addingTimeInterval(-60), expires: Date().addingTimeInterval(600)
            ))
            app.sessions.perform(.open(duration: 300, grant: grant))
            let paris = LocationCoordinate(latitude: 48.8566, longitude: 2.3522)
            let layout = AppGroupStoreLayout(directory: app.receiver.appDirectory)
            let payload = try TransportMessage.payload(LocationSpoofing.Command.spoof(paris))
            let document = StoreDocument(TransportMessage(kind: .command, pluginID: LocationSpoofing.pluginID, payload: payload))
            try layout.write(document.encoded(), to: layout.commands.appending(path: "0.json"))
            let indicator = LocationSpoofingIndicator(spoofing: app.spoofing)
            let real = CLLocation(latitude: 37.3349, longitude: -122.009)

            app.receiver.reevaluateGates()
            let toldAtSpoof = (app.signals.isSpoofed, app.signals.location.map { LocationCoordinate($0.coordinate) })
            app.didUpdateLocations([real])
            let readDuringSession = app.signals.location.map { LocationCoordinate($0.coordinate) }
            let shownDuringSession = indicator.spoofing.snapshot.isSpoofing
            app.sessions.end()
            app.didUpdateLocations([real])

            #expect(toldAtSpoof == (true, paris))
            #expect(readDuringSession == paris)
            #expect(shownDuringSession)
            #expect(!app.signals.isSpoofed)
            #expect(app.signals.location === real)
            #expect(!indicator.spoofing.snapshot.isSpoofing)
        }
    }
#endif
