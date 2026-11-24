# Spoofing the Location in Production

Test geo features on the build that ships by replacing the locations the app reads with a
sidecar's coordinate, for its session.

## Overview

A store finder, a delivery zone or a regional price can be tested this way. Many apps forbid
location spoofing for fraud or compliance reasons, so the capability is off unless the app enables
it, nothing is intercepted, and the app is told as spoofing starts and ends so its own fraud checks
can react. Link `DebugDrawerLocation` (`.product(name: "DebugDrawerLocation", package:
"DebugDrawer")`) beside the receiver, pass the readings a tester should be able to move through the
model, and enable the capability:

```swift
import CoreLocation
import CryptoKit
import DebugDrawerLocation
import DebugDrawerReceiver
import Foundation
import SwiftUI

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
```

### The risk: high

Whoever holds the sidecar, a leaked copy included, can make the app believe the device is anywhere.
That is what location fraud does: claim a region's offer, check in somewhere they aren't, appear
inside a delivery zone.

### Nothing intercepted: only what the app passes through

A release build replaces no method and swaps no delegate. Only the readings the app passes through
`spoofing.location(replacing:)` or `spoofing.locations(replacing:)` are spoofed, so route the ones a
tester should be able to move, and leave the ones your fraud checks rely on reading Core Location
directly. Both are safe from any thread, and so are `spoofing.isSpoofing` and
`spoofing.spoofedLocation`. A spoofed reading is dated when it is read.

### The app is told

`spoofingDidChange`, which the model requires, is called on the main actor with the spoofed
location as a spoof lands or moves, and with `nil` as it ends, whatever ends it.
`spoofing.snapshot.isSpoofing` and `spoofing.isSpoofing` say the same. Raise your own fraud signal
from it (`LocationSignals.isSpoofed` above), and treat what the app read meanwhile as not the
device's.

### A coordinate, only

The sidecar connects to `LocationSpoofing.pluginID` with `LocationSpoofing.Snapshot` (the spoofed
`coordinate`, or `nil`) and `LocationSpoofing.Command`: `spoof(_:)`, with a `LocationCoordinate`,
and `stop`. A coordinate off the Earth (latitude beyond ±90, longitude beyond ±180, or not a number)
is refused as `commandRefused(.malformedCommand)`. Until the app enables `.locationSpoofing(_:)`, a
spoof is refused as `commandRefused(.unknownCapability)`, even inside a session. Outside a session a
spoof is refused (`noActiveSession`), and a spoof handed to the model directly outside one is
ignored.

### A grant when a verifier is configured

With a `DebugDrawerGrantPolicy` on the sessions, as above, a spoof needs a session whose grant lists
`LocationSpoofing.pluginID`. Without a grant no session opens, and a grant for other capabilities is
refused as `commandRefused(.capabilityNotGranted)`. Grants stay optional: without a policy a spoof
needs only a session. Add `.requiringGrant()` to the capability to refuse spoofs as
`commandRefused(.grantMissing)` in any session without one. <doc:SignedGrants> describes grants.

### For the session, always

As the session ends, expires or the receiver's or the capability's gate turns off, the readings are
real again, the app is told `nil`, and the end is audited as `changeReverted`. The readings stop
being spoofed at the session's expiry date even before the sessions' timer fires in an app that was
suspended.

The coordinate is kept in memory only, so a kill ends the spoof with the process. While spoofing, a
flag (never the coordinate) is kept in the defaults, which lets the next launch tell the app `nil`
as it makes the capability, so a location the app kept from that launch can be dropped. Make the
capability as the app starts.

### The app shows it

Show the spoofed location in the session indicator, as `LocationSpoofingIndicator` does, so the
person holding the device knows the app isn't using where they are.

### In the sidecar

The kit's `DebugDrawerSidecarPlugin.locationSpoofing` shows the spoofed location under a high-risk
warning, with latitude and longitude fields, a few places to pick, and Stop Spoofing.
