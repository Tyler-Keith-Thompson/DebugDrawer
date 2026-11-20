import DebugDrawer
import DebugDrawerNetwork
import DebugDrawerSidecarKit
import SwiftUI

extension DebugDrawerSidecarPlugin {
    /// The host's network mocking (`DebugDrawerReceiverCapability.networkMocking`), which needs a
    /// grant listing it.
    @MainActor static var networkMocking: DebugDrawerSidecarPlugin {
        DebugDrawerSidecarPlugin(
            id: NetworkMocking.pluginID, title: "Mocking", icon: "network.badge.shield.half.filled",
            snapshot: NetworkMocking.Snapshot.self, command: NetworkMocking.Command.self
        ) { transport in
            NetworkMockingPlugin(transport: transport)
        }
    }
}

/// The session's rules and conditioning, with presets for the example host's Fetch Greeting: a
/// mocked answer, and the same answer two seconds late.
struct NetworkMockingPlugin: DebugDrawerPlugin {
    let transport: DebugDrawerPluginTransport<NetworkMocking.Snapshot, NetworkMocking.Command>
    let title = "Mocking"
    let icon = "network.badge.shield.half.filled"

    var body: some View {
        NetworkMockingView(transport: transport)
    }
}

private struct NetworkMockingView: View {
    @ObservedObject var transport: DebugDrawerPluginTransport<NetworkMocking.Snapshot, NetworkMocking.Command>

    var body: some View {
        DebugDrawerSection("Allowed hosts") {
            ForEach(transport.snapshot.allowedHosts, id: \.self) { host in
                DebugDrawerKeyValueRow(host.exampleKind, value: host.exampleHost)
            }
        }
        DebugDrawerSection("Rules") {
            if transport.snapshot.rules.isEmpty {
                Text("No rules: every request goes to the network.")
                    .debugDrawerRowPadding()
            }
            ForEach(transport.snapshot.rules) { rule in
                DebugDrawerKeyValueRow(rule.name, value: "\(rule.response.status)")
            }
            ForEach(transport.snapshot.conditions) { profile in
                DebugDrawerKeyValueRow(profile.name, value: profile.latency.formatted())
            }
        } footer: {
            Text(transport.snapshot.isActive ? "Answering the app's requests from these rules." : "Not answering any request.")
        }
        DebugDrawerActionRow {
            Button("Mock Greeting") { transport.send(.setRules([.exampleGreeting])) }
            Button("Slow Greeting") { transport.send(.setConditions([.exampleSlowGreeting])) }
        } trailing: {
            Button("Reset", role: .destructive) { transport.send(.reset) }
                .debugDrawerButtonStyle(.destructive)
        }
    }
}

extension NetworkMockRule {
    /// Answers the example host's Fetch Greeting.
    fileprivate static let exampleGreeting = NetworkMockRule(
        name: "Greeting",
        matcher: Matcher(methods: ["GET"], host: .exact("api.example.com"), path: .exact("/greeting")),
        response: Response(status: 200, body: .text("Hello from the sidecar"), contentType: "text/plain")
    )
}

extension NetworkConditionProfile {
    /// Holds the greeting's answer back two seconds.
    fileprivate static let exampleSlowGreeting = NetworkConditionProfile(
        name: "Slow api.example.com", host: .exact("api.example.com"), latency: .seconds(2)
    )
}

extension NetworkMocking.AllowedHost {
    fileprivate var exampleKind: String {
        switch self {
        case .exact: "Host"
        case .domain: "Domain"
        }
    }

    fileprivate var exampleHost: String {
        switch self {
        case let .exact(host), let .domain(host): host
        }
    }
}
