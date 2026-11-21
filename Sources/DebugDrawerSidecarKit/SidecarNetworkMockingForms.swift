import DebugDrawer
#if canImport(DebugDrawerNetwork)
    import DebugDrawerNetwork
#endif
import Foundation
import SwiftUI

// The Mocking plugin's forms (SidecarNetworkMockingPlugin.swift): a new rule and a new delay, each
// a draft value the form edits and checks, so it holds only what the app would apply.

#if DEBUG && canImport(DebugDrawerNetwork)
    /// What the new-rule form holds as the employee edits it: the request it matches and the
    /// answer, starting at a GET of the first allowed host's `/` answered 200 with an empty JSON
    /// object.
    struct NetworkMockRuleDraft: Equatable {
        /// The methods the form offers; the empty one matches any.
        static let methods = ["GET", "POST", "PUT", "PATCH", "DELETE", ""]

        var host: String
        var method = "GET"
        var path = "/"
        var status = "200"
        var body = "{}"
        var contentType = "application/json"

        init(allowedHosts: [NetworkMocking.AllowedHost]) {
            host = allowedHosts.first?.name ?? ""
        }

        /// The rule the form holds, or `nil` while it holds none the app would answer from: a host
        /// it doesn't allow, a path that doesn't start with `/`, a status outside 100...599.
        func rule(allowedHosts: [NetworkMocking.AllowedHost]) -> NetworkMockRule? {
            let host = host.trimmingCharacters(in: .whitespaces)
            let path = path.trimmingCharacters(in: .whitespaces)
            guard allowedHosts.contains(where: { $0.allows(host) }), path.hasPrefix("/"),
                  let status = Int(status.trimmingCharacters(in: .whitespaces)), (100 ... 599).contains(status)
            else { return nil }
            let contentType = contentType.trimmingCharacters(in: .whitespaces)
            return NetworkMockRule(
                name: "\(method.isEmpty ? "Any" : method) \(host)\(path)",
                matcher: NetworkMockRule.Matcher(
                    methods: method.isEmpty ? [] : [method], host: .exact(host), path: path.contains("*") ? .wildcard(path) : .exact(path)
                ),
                response: NetworkMockRule.Response(
                    status: status, body: body.isEmpty ? .empty : .text(body), contentType: contentType.isEmpty ? nil : contentType
                )
            )
        }
    }

    /// The form for a new rule, and Add Rule, enabled while it holds one the app would answer from.
    struct NetworkMockRuleForm: View {
        let allowedHosts: [NetworkMocking.AllowedHost]
        let add: (NetworkMockRule) -> Void
        @State private var draft: NetworkMockRuleDraft

        init(allowedHosts: [NetworkMocking.AllowedHost], add: @escaping (NetworkMockRule) -> Void) {
            self.allowedHosts = allowedHosts
            self.add = add
            _draft = State(initialValue: NetworkMockRuleDraft(allowedHosts: allowedHosts))
        }

        var body: some View {
            DebugDrawerRow("New Rule", systemImage: "plus.circle") {
                field("Host", text: $draft.host)
                Picker("Method", selection: $draft.method) {
                    ForEach(NetworkMockRuleDraft.methods, id: \.self) { method in
                        Text(method.isEmpty ? "Any" : method).tag(method)
                    }
                }
                .accessibilityLabel("Method")
                field("Path", text: $draft.path)
                field("Status", text: $draft.status)
                field("Body", text: $draft.body)
                field("Content Type", text: $draft.contentType)
                DebugDrawerActionRow {
                    Button("Add Rule") {
                        if let rule = draft.rule(allowedHosts: allowedHosts) {
                            add(rule)
                        }
                    }
                    .debugDrawerButtonStyle(.primary)
                    .disabled(draft.rule(allowedHosts: allowedHosts) == nil)
                    .accessibilityLabel("Add Rule")
                    .accessibilityHint("Answers the requests it matches from now on")
                }
            } accessory: {
                EmptyView()
            }
            .accessibilityIdentifier("NetworkRuleForm")
        }

        private func field(_ title: String, text: Binding<String>) -> some View {
            TextField(title, text: text, prompt: Text(title))
                .debugDrawerTextFieldStyle()
                .accessibilityLabel(title)
        }
    }

    /// What the new-delay form holds: a host the app allows and a latency in milliseconds.
    struct NetworkDelayDraft: Equatable {
        var host: String
        var milliseconds = "2000"

        init(allowedHosts: [NetworkMocking.AllowedHost]) {
            host = allowedHosts.first?.name ?? ""
        }

        /// The delay the form holds, or `nil` while the host isn't allowed or the latency isn't a
        /// whole number of milliseconds from 1 to 60,000.
        func profile(allowedHosts: [NetworkMocking.AllowedHost]) -> NetworkConditionProfile? {
            let host = host.trimmingCharacters(in: .whitespaces)
            guard allowedHosts.contains(where: { $0.allows(host) }),
                  let milliseconds = Int(milliseconds.trimmingCharacters(in: .whitespaces)), (1 ... 60000).contains(milliseconds)
            else { return nil }
            return NetworkConditionProfile(name: "Delay \(host)", host: .exact(host), latency: .milliseconds(milliseconds))
        }
    }

    /// The form for a new delay, and Add Delay, enabled while it holds one.
    struct NetworkDelayForm: View {
        let allowedHosts: [NetworkMocking.AllowedHost]
        let add: (NetworkConditionProfile) -> Void
        @State private var draft: NetworkDelayDraft

        init(allowedHosts: [NetworkMocking.AllowedHost], add: @escaping (NetworkConditionProfile) -> Void) {
            self.allowedHosts = allowedHosts
            self.add = add
            _draft = State(initialValue: NetworkDelayDraft(allowedHosts: allowedHosts))
        }

        var body: some View {
            DebugDrawerRow("New Delay", systemImage: "plus.circle") {
                TextField("Host", text: $draft.host, prompt: Text("Host"))
                    .debugDrawerTextFieldStyle()
                    .accessibilityLabel("Delay Host")
                TextField("Milliseconds", text: $draft.milliseconds, prompt: Text("Milliseconds"))
                    .debugDrawerTextFieldStyle()
                    .accessibilityLabel("Delay in Milliseconds")
                DebugDrawerActionRow {
                    Button("Add Delay") {
                        if let profile = draft.profile(allowedHosts: allowedHosts) {
                            add(profile)
                        }
                    }
                    .debugDrawerButtonStyle(.primary)
                    .disabled(draft.profile(allowedHosts: allowedHosts) == nil)
                    .accessibilityLabel("Add Delay")
                    .accessibilityHint("Holds back the mocked answers to the host from now on")
                }
            } accessory: {
                EmptyView()
            }
            .accessibilityIdentifier("NetworkDelayForm")
        }
    }
#endif
