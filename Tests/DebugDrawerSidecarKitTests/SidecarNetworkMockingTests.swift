// The Network capability module isn't built for watchOS, so neither is the kit's plugin for it.
#if DEBUG && os(macOS)
    import DebugDrawer
    @testable import DebugDrawerNetwork
    @testable import DebugDrawerSidecarKit
    import Foundation
    import Testing
    import ViewInspector

    // The Mocking plugin as a function of the capability's snapshot: every change sends the whole
    // list the app answers from, and the forms hold only rules and delays the app would apply.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct SidecarNetworkMockingTests {
        private let allowed: [NetworkMocking.AllowedHost] = [.exact("api.example.com"), .domain("example.org")]
        private let greeting = NetworkMockRule(
            name: "Greeting",
            matcher: .init(methods: ["GET"], host: .exact("api.example.com"), path: .exact("/greeting")),
            response: .init(status: 200, body: .text("Hello"), contentType: "text/plain")
        )
        private let slow = NetworkConditionProfile(name: "Slow API", host: .exact("api.example.com"), latency: .seconds(2))

        @Test("A rule's switch and Remove send the rules with it off or without it; a delay's the same; Reset sends reset")
        func rowsSendWholeLists() throws {
            let snapshot = NetworkMocking.Snapshot(sessionID: UUID(), allowedHosts: allowed, rules: [greeting], conditions: [slow])
            var sent: [NetworkMocking.Command] = []
            let sut = NetworkMockingView(snapshot: snapshot) { sent.append($0) }
            var off = greeting
            off.isEnabled = false
            var slowOff = slow
            slowOff.isEnabled = false

            try sut.inspect().find(viewWithAccessibilityIdentifier: "NetworkRule-Greeting").find(ViewType.Toggle.self).tap()
            try sut.inspect().find(viewWithAccessibilityIdentifier: "NetworkRule-Greeting").find(button: "Remove").tap()
            try sut.inspect().find(viewWithAccessibilityIdentifier: "NetworkDelay-Slow API").find(ViewType.Toggle.self).tap()
            try sut.inspect().find(viewWithAccessibilityIdentifier: "NetworkDelay-Slow API").find(button: "Remove").tap()
            try sut.inspect().find(button: "Reset").tap()

            #expect(sent == [.setRules([off]), .setRules([]), .setConditions([slowOff]), .setConditions([]), .reset])
            #expect(throws: Never.self) { try sut.inspect().find(text: "GET api.example.com /greeting") }
            #expect(throws: Never.self) { try sut.inspect().find(text: "Answering the app's requests from these rules.") }
            #expect(throws: Never.self) { try sut.inspect().find(text: "Domain") }
        }

        @Test("A preset adds itself after the session's rules, and reads Added once they hold it, whatever its ID")
        func presetsAdd() throws {
            let other = NetworkMockRule(name: "Other", matcher: .init(host: .exact("api.example.com")), response: .init(status: 404))
            var sent: [NetworkMocking.Command] = []
            let empty = NetworkMocking.Snapshot(sessionID: UUID(), allowedHosts: allowed, rules: [other], conditions: [])
            let holding = NetworkMocking.Snapshot(
                sessionID: UUID(), allowedHosts: allowed,
                rules: [NetworkMockRule(name: greeting.name, matcher: greeting.matcher, response: greeting.response)], conditions: [slow]
            )
            let adding = NetworkMockingView(snapshot: empty, presets: [greeting], conditionPresets: [slow]) { sent.append($0) }
            let added = NetworkMockingView(snapshot: holding, presets: [greeting], conditionPresets: [slow]) { _ in }

            try adding.inspect().find(viewWithAccessibilityIdentifier: "NetworkPreset-Greeting").find(button: "Add").tap()
            try adding.inspect().find(viewWithAccessibilityIdentifier: "NetworkPreset-Slow API").find(button: "Add").tap()

            #expect(sent == [.setRules([other, greeting]), .setConditions([slow])])
            #expect(throws: Never.self) { try added.inspect().find(viewWithAccessibilityIdentifier: "NetworkPreset-Greeting").find(text: "Added") }
            #expect(throws: (any Error).self) {
                try added.inspect().find(viewWithAccessibilityIdentifier: "NetworkPreset-Slow API").find(button: "Add")
            }
        }

        @Test("The new-rule form starts at a GET of the first allowed host's / answered 200, and Add Rule appends it")
        func formAddsDefaultRule() throws {
            let snapshot = NetworkMocking.Snapshot(sessionID: UUID(), allowedHosts: allowed, rules: [greeting], conditions: [])
            var sent: [NetworkMocking.Command] = []
            let sut = NetworkMockingView(snapshot: snapshot) { sent.append($0) }

            try sut.inspect().find(viewWithAccessibilityIdentifier: "NetworkRuleForm").find(button: "Add Rule").tap()

            guard case let .setRules(rules) = try #require(sent.first) else {
                Issue.record("Add Rule sent \(sent)")
                return
            }
            let added = try #require(rules.last)
            #expect(rules.count == 2)
            #expect(rules.first == greeting)
            #expect(added.name == "GET api.example.com/")
            #expect(added.matcher == NetworkMockRule.Matcher(methods: ["GET"], host: .exact("api.example.com"), path: .exact("/")))
            #expect(added.response == NetworkMockRule.Response(status: 200, body: .text("{}"), contentType: "application/json"))
        }

        @Test("A rule draft holds a rule only for an allowed host, a path from /, and a status from 100 to 599; * makes a wildcard path")
        func ruleDraftChecks() {
            var sut = NetworkMockRuleDraft(allowedHosts: allowed)

            sut.host = "evil.example.net"
            let disallowedHost = sut.rule(allowedHosts: allowed)
            sut.host = "cdn.example.org"
            sut.path = "greeting"
            let relativePath = sut.rule(allowedHosts: allowed)
            sut.path = "/users/*"
            sut.status = "600"
            let badStatus = sut.rule(allowedHosts: allowed)
            sut.status = " 503 "
            sut.method = ""
            sut.body = ""
            sut.contentType = ""
            let valid = sut.rule(allowedHosts: allowed)

            #expect(disallowedHost == nil)
            #expect(relativePath == nil)
            #expect(badStatus == nil)
            #expect(valid?.matcher == NetworkMockRule.Matcher(host: .exact("cdn.example.org"), path: .wildcard("/users/*")))
            #expect(valid?.response == NetworkMockRule.Response(status: 503, body: .empty, contentType: nil))
            #expect(valid?.name == "Any cdn.example.org/users/*")
        }

        @Test("A delay draft holds a delay only for an allowed host and 1 to 60,000 milliseconds")
        func delayDraftChecks() {
            var sut = NetworkDelayDraft(allowedHosts: allowed)

            let start = sut.profile(allowedHosts: allowed)
            sut.milliseconds = "0"
            let zero = sut.profile(allowedHosts: allowed)
            sut.milliseconds = "60001"
            let tooLong = sut.profile(allowedHosts: allowed)
            sut.milliseconds = "250"
            sut.host = "example.com"
            let disallowed = sut.profile(allowedHosts: allowed)

            #expect(start?.host == .exact("api.example.com"))
            #expect(start?.latency == .milliseconds(2000))
            #expect(zero == nil)
            #expect(tooLong == nil)
            #expect(disallowed == nil)
        }

        @Test("With no host allowed the plugin says it mocks nothing, and the form adds nothing")
        func noAllowedHosts() throws {
            let snapshot = NetworkMocking.Snapshot(sessionID: UUID(), allowedHosts: [], rules: [], conditions: [])
            var sent: [NetworkMocking.Command] = []
            let sut = NetworkMockingView(snapshot: snapshot) { sent.append($0) }

            #expect(throws: Never.self) { try sut.inspect().find(text: "The app allows no host, so it mocks nothing.") }
            #expect(try sut.inspect().find(button: "Add Rule").isDisabled())
            #expect(throws: (any Error).self) { try sut.inspect().find(button: "Reset") }
            #expect(sent.isEmpty)
        }

        @Test("The shipped Mocking plugin is served under the capability's ID, with presets or without")
        func shippedPlugin() {
            let plain = DebugDrawerSidecarPlugin.networkMocking
            let withPresets = DebugDrawerSidecarPlugin.networkMocking(presets: [greeting])

            #expect([plain.id, plain.title, plain.icon] == [NetworkMocking.pluginID, "Mocking", "network.badge.shield.half.filled"])
            #expect(withPresets.id == NetworkMocking.pluginID)
        }
    }
#endif
