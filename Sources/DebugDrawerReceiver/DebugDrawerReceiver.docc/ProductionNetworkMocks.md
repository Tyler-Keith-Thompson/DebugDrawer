# Mocking the Network in Production

Reproduce a server's edge case on the build that ships by answering some of the app's requests
with a sidecar's mock rules, for its session, on hosts the app allows.

## Overview

A sidecar can simulate an outage, an empty list, or a slow or failing endpoint. The capability is
off unless the app enables it, and it requires a grant (<doc:SignedGrants>). Link
`DebugDrawerNetwork` (`.product(name: "DebugDrawerNetwork", package: "DebugDrawer")`) beside the
receiver. It is the UI-free half of the Network plugin and holds `NetworkMockRule` and
`NetworkConditionProfile`. Make the model with the hosts a sidecar may mock, enable the capability,
and list the capability's URL protocol in each session whose requests may be mocked:

```swift
import CryptoKit
import DebugDrawerNetwork
import DebugDrawerReceiver
import Foundation

@MainActor
final class ProductionNetworkMocking {
    let sessions: DebugDrawerSessions
    let receiver: DebugDrawerReceiver
    let mocking: NetworkMocking
    let apiSession: URLSession

    init(grantServerKey: Curve25519.Signing.PublicKey, container: URL) throws {
        sessions = DebugDrawerSessions(maximumDuration: 15 * 60, grantPolicy: DebugDrawerGrantPolicy(
            verifier: DebugDrawerSignedGrantVerifier(keys: [.ed25519(grantServerKey)]),
            audience: "com.example.MyApp"
        ))
        mocking = NetworkMocking(sessions: sessions, allowedHosts: [.exact("api.example.com"), .domain("staging.example.com")])
        receiver = DebugDrawerReceiver(directory: container.appending(path: "DebugDrawer"), sessions: sessions)
        receiver.enable(.networkMocking(mocking))
        try receiver.start()

        let configuration = URLSessionConfiguration.default
        configuration.protocolClasses = [NetworkMockingURLProtocol.self] + (configuration.protocolClasses ?? [])
        apiSession = URLSession(configuration: configuration)
    }
}
```

The sidecar, in a session whose grant lists `NetworkMocking.pluginID`, sends the rules:

```swift
// In the sidecar, once its session is open:
mocks.send(.setRules([NetworkMockRule(
    name: "Orders outage",
    matcher: .init(methods: ["GET"], host: .exact("api.example.com"), path: .wildcard("/v1/orders/**")),
    response: .init(status: 503, body: .text(#"{"error":"maintenance"}"#), contentType: "application/json")
)]))
```

### Only the sessions the app configures

Nothing is registered with URL loading and no method is replaced. `NetworkMockingURLProtocol`
answers only for a `URLSession` whose configuration lists it, as above; `URLSession.shared` and
every other session are never touched. It claims only a request that a rule of the open session
matches, over HTTP or HTTPS, to an allowed host, and declines the rest, which load as if it weren't
listed. It never sends a request or reads a server's response, and an answer never enters the
session's cache.

### Only allowed hosts

`allowedHosts` is the app's, fixed as it makes the model. `.exact(_:)` allows one host, and
`.domain(_:)` allows the domain and every host under it (`.domain("example.com")` allows
`api.example.com`, not `badexample.com`), ignoring case. A request to any other host is never
answered, whatever a rule matches; with an empty list nothing is.

### Only during a granted session

The sidecar connects to `NetworkMocking.pluginID` with `NetworkMocking.Snapshot` (the open
session's ID, the allowed hosts, its rules and profiles) and `NetworkMocking.Command`.
`setRules(_:)` and `setConditions(_:)` replace the session's rules or profiles, and `reset` removes
them.

The capability requires a grant listing it even in a receiver without a grant policy, where its
commands are refused as `commandRefused(.grantMissing)`. Under a policy, a session whose grant
doesn't list it is refused as `.capabilityNotGranted`. Each session starts with no rules. As it
ends, expires (from the expiry date, before the system's timer fires) or the receiver's or the
capability's gate turns off, every request reaches the server again.

### Rules as the plugin's, with two limits

A rule matches and answers as described in the Network plugin documentation's Mocking Responses
article, and the first rule that is on answers. A sidecar's rule may not use a regular expression
or a file body. Either is refused as `commandRefused(.malformedCommand)`, because no
received expression is evaluated in the app and the sidecar can't place a file in the app's
storage. Use exact and wildcard patterns and a text body.

### Conditioning shapes the answers

A profile from `setConditions(_:)`, as described in the Network plugin documentation's Simulating
Network Conditions article, delays a rule's answer by its latency, delivers its body no faster
than its bandwidth, or fails it with its failure and rate. It applies only to the requests a rule answers. A request no rule matches goes to the
server as it is, unslowed, as the app never sends one through the library.

### The app shows it

`mocking.snapshot.isActive` is `true` while a session is open with a rule on and a host allowed.
Show it with the session indicator, so the person holding the device knows the responses may not be
the server's:

```swift
struct NetworkMockingIndicator: View {
    @ObservedObject var mocking: NetworkMocking

    var body: some View {
        if mocking.snapshot.isActive {
            Label("Network mocking active", systemImage: "exclamationmark.icloud")
        }
    }
}
```
