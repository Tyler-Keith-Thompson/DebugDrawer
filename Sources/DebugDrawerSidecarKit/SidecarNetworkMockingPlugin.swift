import DebugDrawer
#if canImport(DebugDrawerNetwork)
    import DebugDrawerNetwork
#endif
import Foundation
import SwiftUI

// The sidecar's half of network mocking (DD-121): the hosts the app allows (`NetworkMocking`, in
// DebugDrawerNetwork), the session's rules and delays, each turned on or off or removed, a form
// for a new rule (host, method, path, status, body) and one for a delay, the sidecar's presets as
// one-tap additions, and Reset. It ships in the kit, as the rules are the library's own, so every
// sidecar would draw the same editor. The capability always needs a grant, so the plugin only
// sends; the app refuses without one. Every change sends the whole list (`setRules`,
// `setConditions`), as the capability takes it, so what the sidecar shows is what the app answers
// from. The form takes an exact host the app allows (the app answers no other) and an exact path,
// or a wildcard one with `*`; never a regular expression, which the app refuses.
// DebugDrawerNetwork doesn't build for watchOS, so the kit has no `networkMocking` there
// (PLATFORM_CONDITIONAL_DEPENDENCIES in scripts/modules.py).
//
// Rejected: presets only (a sidecar could mock only what was compiled into it), and a body editor
// with files (`.file` bodies name the debug plugin's storage, which a production app doesn't have).

#if DEBUG && canImport(DebugDrawerNetwork)
    extension DebugDrawerSidecarPlugin {
        /// The app's network mocking (`DebugDrawerReceiverCapability.networkMocking(_:)`), which
        /// needs a grant listing it: the hosts the app allows, the session's rules and delays, and
        /// a form for each.
        @MainActor public static var networkMocking: DebugDrawerSidecarPlugin {
            networkMocking(presets: [])
        }

        /// The app's network mocking, with rules and delays the sidecar offers as one-tap
        /// additions beside the forms: the answers a team mocks often.
        ///
        /// ```swift
        /// let greeting = NetworkMockRule(
        ///     name: "Greeting",
        ///     matcher: .init(methods: ["GET"], host: .exact("api.example.com"), path: .exact("/greeting")),
        ///     response: .init(status: 200, body: .text("Hello"), contentType: "text/plain")
        /// )
        /// DebugDrawerSidecarView(groupIdentifier: "group.com.example.debug", plugins: [.networkMocking(presets: [greeting])])
        /// ```
        ///
        /// - Parameters:
        ///   - presets: Rules to add with one tap; one already in the session's rules (the same
        ///     name, matcher and response) is marked added.
        ///   - conditionPresets: Delays and failures to add with one tap.
        @MainActor public static func networkMocking(
            presets: [NetworkMockRule], conditionPresets: [NetworkConditionProfile] = []
        ) -> DebugDrawerSidecarPlugin {
            DebugDrawerSidecarPlugin(
                id: NetworkMocking.pluginID, title: "Mocking", icon: "network.badge.shield.half.filled",
                snapshot: NetworkMocking.Snapshot.self, command: NetworkMocking.Command.self
            ) { transport in
                NetworkMockingSidecarPlugin(transport: transport, presets: presets, conditionPresets: conditionPresets)
            }
        }
    }

    /// The app's network mocking, edited from the sidecar.
    struct NetworkMockingSidecarPlugin: DebugDrawerPlugin {
        let transport: DebugDrawerPluginTransport<NetworkMocking.Snapshot, NetworkMocking.Command>
        let presets: [NetworkMockRule]
        let conditionPresets: [NetworkConditionProfile]
        let title = "Mocking"
        let icon = "network.badge.shield.half.filled"

        var body: some View {
            NetworkMockingTransportView(transport: transport, presets: presets, conditionPresets: conditionPresets)
        }
    }

    /// The rules over the capability's snapshot, sending what the view asks.
    struct NetworkMockingTransportView: View {
        @ObservedObject var transport: DebugDrawerPluginTransport<NetworkMocking.Snapshot, NetworkMocking.Command>
        let presets: [NetworkMockRule]
        let conditionPresets: [NetworkConditionProfile]

        var body: some View {
            NetworkMockingView(snapshot: transport.snapshot, presets: presets, conditionPresets: conditionPresets) { transport.send($0) }
        }
    }

    /// The allowed hosts, the rules and delays with their switches and Remove, the presets, the
    /// forms, and Reset. A function of the snapshot, the presets and the send action.
    struct NetworkMockingView: View {
        let snapshot: NetworkMocking.Snapshot
        var presets: [NetworkMockRule] = []
        var conditionPresets: [NetworkConditionProfile] = []
        let send: (NetworkMocking.Command) -> Void

        var body: some View {
            DebugDrawerSection("Allowed Hosts") {
                if snapshot.allowedHosts.isEmpty {
                    note("The app allows no host, so it mocks nothing.")
                }
                ForEach(snapshot.allowedHosts, id: \.self) { host in
                    DebugDrawerKeyValueRow(host.kindTitle, value: host.name)
                }
            }
            DebugDrawerSection("Rules") {
                if snapshot.rules.isEmpty {
                    note("No rules: every request goes to the network.")
                }
                ForEach(snapshot.rules) { rule in
                    NetworkMockRuleRow(rule: rule) { isEnabled in
                        send(.setRules(snapshot.rules.map { $0.id == rule.id ? $0.enabled(isEnabled) : $0 }))
                    } remove: {
                        send(.setRules(snapshot.rules.filter { $0.id != rule.id }))
                    }
                }
                ForEach(presets) { preset in
                    presetRow(preset.name, isAdded: snapshot.rules.contains { $0.isSameRule(as: preset) }) {
                        send(.setRules(snapshot.rules + [preset]))
                    }
                }
                NetworkMockRuleForm(allowedHosts: snapshot.allowedHosts) { send(.setRules(snapshot.rules + [$0])) }
            } footer: {
                Text(snapshot.isActive ? "Answering the app's requests from these rules." : "Not answering any request.")
            }
            DebugDrawerSection("Delays") {
                if snapshot.conditions.isEmpty {
                    note("No delays: mocked answers arrive at once.")
                }
                ForEach(snapshot.conditions) { profile in
                    NetworkConditionRow(profile: profile) { isEnabled in
                        send(.setConditions(snapshot.conditions.map { $0.id == profile.id ? $0.enabled(isEnabled) : $0 }))
                    } remove: {
                        send(.setConditions(snapshot.conditions.filter { $0.id != profile.id }))
                    }
                }
                ForEach(conditionPresets) { preset in
                    presetRow(preset.name, isAdded: snapshot.conditions.contains { $0.isSameProfile(as: preset) }) {
                        send(.setConditions(snapshot.conditions + [preset]))
                    }
                }
                NetworkDelayForm(allowedHosts: snapshot.allowedHosts) { send(.setConditions(snapshot.conditions + [$0])) }
            } footer: {
                Text("A delay holds back the mocked answers to its host; requests the rules don't answer aren't delayed.")
            }
            if !snapshot.rules.isEmpty || !snapshot.conditions.isEmpty {
                DebugDrawerActionRow {
                    EmptyView()
                } trailing: {
                    Button("Reset", role: .destructive) { send(.reset) }
                        .debugDrawerButtonStyle(.destructive)
                        .accessibilityLabel("Reset")
                        .accessibilityHint("Removes every rule and delay; the app's requests go to the network")
                }
            }
        }

        private func note(_ text: String) -> some View {
            Text(text)
                .debugDrawerFont(.label)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .debugDrawerRowPadding()
        }

        private func presetRow(_ name: String, isAdded: Bool, add: @escaping () -> Void) -> some View {
            DebugDrawerRow(name, systemImage: "star") {
                if isAdded {
                    Text("Added")
                        .debugDrawerForegroundStyle(.accent)
                } else {
                    Button("Add", action: add)
                        .debugDrawerButtonStyle(.primary)
                        .accessibilityLabel("Add \(name)")
                }
            }
            .accessibilityIdentifier("NetworkPreset-\(name)")
        }
    }

    /// One rule: its name, what it matches and answers, its switch and Remove.
    struct NetworkMockRuleRow: View {
        let rule: NetworkMockRule
        let setEnabled: (Bool) -> Void
        let remove: () -> Void

        var body: some View {
            DebugDrawerRow(rule.name, systemImage: nil) {
                Text(rule.matcher.summary)
                Text("Answers \(rule.response.status)")
                Button("Remove", role: .destructive, action: remove)
                    .debugDrawerButtonStyle(.secondary)
                    .accessibilityLabel("Remove \(rule.name)")
            } accessory: {
                Toggle(isOn: Binding { rule.isEnabled } set: { setEnabled($0) }) {
                    Text(rule.name)
                }
                .labelsHidden()
                .accessibilityLabel(rule.name)
            }
            .accessibilityIdentifier("NetworkRule-\(rule.name)")
        }
    }

    /// One delay: its name, its host, latency and failures, its switch and Remove.
    struct NetworkConditionRow: View {
        let profile: NetworkConditionProfile
        let setEnabled: (Bool) -> Void
        let remove: () -> Void

        var body: some View {
            DebugDrawerRow(profile.name, systemImage: nil) {
                Text(profile.host.summary)
                Text(profile.effectSummary)
                Button("Remove", role: .destructive, action: remove)
                    .debugDrawerButtonStyle(.secondary)
                    .accessibilityLabel("Remove \(profile.name)")
            } accessory: {
                Toggle(isOn: Binding { profile.isEnabled } set: { setEnabled($0) }) {
                    Text(profile.name)
                }
                .labelsHidden()
                .accessibilityLabel(profile.name)
            }
            .accessibilityIdentifier("NetworkDelay-\(profile.name)")
        }
    }

    extension NetworkMocking.AllowedHost {
        /// Whether it allows one host or a domain, as a row names it.
        fileprivate var kindTitle: String {
            switch self {
            case .exact: "Host"
            case .domain: "Domain"
            }
        }

        /// The host or domain.
        var name: String {
            switch self {
            case let .exact(host), let .domain(host): host
            }
        }
    }

    extension NetworkMockRule {
        /// Whether it is `other` whatever its ID and switch: a preset made again, with a new ID,
        /// still reads as added.
        fileprivate func isSameRule(as other: Self) -> Bool {
            name == other.name && matcher == other.matcher && response == other.response
        }

        /// The rule, on or off.
        fileprivate func enabled(_ isEnabled: Bool) -> Self {
            var rule = self
            rule.isEnabled = isEnabled
            return rule
        }
    }

    extension NetworkConditionProfile {
        /// Whether it is `other` whatever its ID and switch.
        fileprivate func isSameProfile(as other: Self) -> Bool {
            name == other.name && host == other.host && latency == other.latency && bandwidth == other.bandwidth
                && failureRate == other.failureRate && failure == other.failure
        }

        /// The profile, on or off.
        fileprivate func enabled(_ isEnabled: Bool) -> Self {
            var profile = self
            profile.isEnabled = isEnabled
            return profile
        }

        /// Its latency, bandwidth and failures, as a row says them.
        fileprivate var effectSummary: String {
            var parts = ["\(latency.formatted(.units(allowed: [.seconds, .milliseconds], width: .abbreviated))) late"]
            if let bandwidth {
                parts.append("\(bandwidth.formatted(.byteCount(style: .file)))/s")
            }
            if failureRate > 0 {
                parts.append("\(failureRate)% fail")
            }
            return parts.joined(separator: ", ")
        }
    }

    extension NetworkMockRule.Matcher {
        /// The methods, host and path it matches, as a row says them: `GET api.example.com /greeting`.
        fileprivate var summary: String {
            let methods = methods.isEmpty ? "Any" : methods.sorted().joined(separator: ", ")
            return "\(methods) \(host.summary) \(path.summary)"
        }
    }

    extension NetworkMockRule.Pattern {
        /// The pattern as a row says it.
        fileprivate var summary: String {
            switch self {
            case .any: "any"
            case let .exact(text), let .wildcard(text): text
            case let .regex(pattern): "/\(pattern)/"
            }
        }
    }
#elseif canImport(DebugDrawerNetwork)
    // The release stand-in: the same members, over a plugin that draws nothing; a release build's
    // transports connect to nothing anyway.

    extension DebugDrawerSidecarPlugin {
        /// The app's network mocking; release builds show nothing.
        @MainActor public static var networkMocking: DebugDrawerSidecarPlugin {
            networkMocking(presets: [])
        }

        /// The app's network mocking, with presets; release builds show nothing.
        @MainActor public static func networkMocking(
            presets _: [NetworkMockRule], conditionPresets _: [NetworkConditionProfile] = []
        ) -> DebugDrawerSidecarPlugin {
            DebugDrawerSidecarPlugin(
                id: NetworkMocking.pluginID, title: "Mocking", icon: "network.badge.shield.half.filled",
                snapshot: NetworkMocking.Snapshot.self, command: NetworkMocking.Command.self
            ) { _ in
                NetworkMockingSidecarPlugin()
            }
        }
    }

    /// Draws nothing.
    struct NetworkMockingSidecarPlugin: DebugDrawerPlugin {
        let title = "Mocking"
        let icon = "network.badge.shield.half.filled"

        var body: some View {
            EmptyView()
        }
    }
#endif
