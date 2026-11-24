# Simulating Network Conditions

Make one host slow or unreliable, without slowing the rest of the device.

## Overview

The Network plugin can make a host slow or unreliable without the Network Link Conditioner. A
conditioning profile applies to one host (matched exactly, by a wildcard or by a regex, as a mock
rule's host is; see <doc:MockingResponses>) or to every host. It adds latency, caps the bandwidth
at which the response's body arrives, and fails a share of the requests with a timeout
(`URLError(.timedOut)`), no connection (`URLError(.notConnectedToInternet)`) or an HTTP 500.
Profiles are made in the drawer (Add Condition, with presets for 3G, Edge and a lossy network), or
passed to `installNetwork(conditions:)`:

```swift
import DebugDrawerNetworkPlugin

let slowImages = NetworkConditionProfile(
    id: UUID(uuidString: "8C4F2A61-7B3D-4E59-A1C8-2D6E9F0B3A47")!,
    name: "Slow images",
    host: .wildcard("*.cdn.example.com"),
    latency: .seconds(2),
    bandwidth: 50_000
)
let paymentsOffline = NetworkConditionProfile(
    id: UUID(uuidString: "5E9B1D73-2C48-4F6A-B0E5-7A3C8D1F2E96")!,
    name: "Payments offline",
    host: .exact("payments.example.com"),
    failureRate: 100,
    failure: .notConnectedToInternet
)
DebugDrawer.shared.installNetwork(conditions: [slowImages, paymentsOffline])
```

### How a profile applies

The bandwidth is in bytes a second and the failure rate in percent. The first profile that is on
and matches a request's host applies. A request to a host no profile matches is untouched.

A conditioned request waits out the latency first. Then it either fails (each request rolls
afresh) or gets its answer: a mock rule's, when one matches, or else the server's, read whole and
then delivered no faster than the cap. Uploads aren't capped.

### In the drawer

The Conditions section, below Mocks, lists each profile with a switch and what it does. While any
profile is on, the plugin's header counts them ("1 active"). Pin the Network plugin to the HUD to
see which ones with the drawer closed ("Slow images active").

A conditioned request shows Conditioned in the log, and its detail names the profile and what it
did ("Delayed 2,000 ms · Failed: timeout"). `network.har` says so too.

### Storage

Profiles are saved beside the mock rules, in `conditions.json`. A profile passed to
`installNetwork(conditions:)` is added once, by its `id`.
