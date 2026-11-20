// The model and the route the URL protocol reads, without URL loading: each test gives the model a
// route of its own, so none shares the process's one and the suite runs alongside the others.
#if DEBUG
    import DebugDrawer
    @testable import DebugDrawerNetwork
    @testable import DebugDrawerReceiver
    import Foundation
    import Testing

    @MainActor
    struct NetworkMockingTests {
        private static let start = Date(timeIntervalSince1970: 1_778_307_200)

        @Test("A session opens with no rules, and its end takes the rules out of the route")
        func followsTheSession() throws {
            let clock = MovableClock(Self.start)
            let route = NetworkMockingRoute()
            let sessions = DebugDrawerSessions(maximumDuration: 600, auditCapacity: 100, clock: clock, timer: ManualTimer())
            let sut = NetworkMocking(
                sessions: sessions, allowedHosts: [.domain("example.com")],
                scheduler: ManualNetworkConditionScheduler(), random: FixedNetworkConditionRandomSource(0), now: { clock.now }, route: route
            )
            let url = try #require(URL(string: "https://api.example.com/v1/orders"))
            let rule = NetworkMockRule(name: "Orders", matcher: .init(path: .exact("/v1/orders")), response: .init(status: 503))

            let beforeSession = sut.snapshot
            sessions.perform(.open(duration: 60))
            let openedSessionID = sessions.snapshot.session?.id
            let opened = sut.snapshot
            sut.perform(.setRules([rule]))
            let claimedDuring = route.claims(method: "GET", url: url)
            let activeDuring = sut.snapshot.isActive
            sessions.end()
            let claimedAfter = route.claims(method: "GET", url: url)

            #expect(beforeSession == NetworkMocking.Snapshot(sessionID: nil, allowedHosts: [.domain("example.com")], rules: [], conditions: []))
            #expect(openedSessionID != nil)
            #expect(opened.sessionID == openedSessionID)
            #expect(opened.rules.isEmpty)
            #expect(claimedDuring)
            #expect(activeDuring)
            #expect(!claimedAfter)
            #expect(sut.snapshot == NetworkMocking.Snapshot(sessionID: nil, allowedHosts: [.domain("example.com")], rules: [], conditions: []))
        }

        @Test("Rules set while no session is open answer nothing, and the next session starts without them")
        func rulesOutsideASession() throws {
            let clock = MovableClock(Self.start)
            let route = NetworkMockingRoute()
            let sessions = DebugDrawerSessions(maximumDuration: 600, auditCapacity: 100, clock: clock, timer: ManualTimer())
            let sut = NetworkMocking(
                sessions: sessions, allowedHosts: [.domain("example.com")],
                scheduler: ManualNetworkConditionScheduler(), random: FixedNetworkConditionRandomSource(0), now: { clock.now }, route: route
            )
            let url = try #require(URL(string: "https://api.example.com/"))

            sut.perform(.setRules([NetworkMockRule(name: "All", matcher: .init(), response: .init())]))
            let claimedWithoutSession = route.claims(method: "GET", url: url)
            sessions.perform(.open(duration: 60))
            defer { sessions.end() }

            #expect(!claimedWithoutSession)
            #expect(sut.snapshot.rules.isEmpty)
            #expect(!route.claims(method: "GET", url: url))
        }

        @Test("The route answers only while the session's expiry is ahead, only allowed hosts, only HTTP and HTTPS, and only rules that are on")
        func routeLimits() throws {
            let clock = MovableClock(Self.start)
            let route = NetworkMockingRoute()
            let sessions = DebugDrawerSessions(maximumDuration: 600, auditCapacity: 100, clock: clock, timer: ManualTimer())
            let sut = NetworkMocking(
                sessions: sessions, allowedHosts: [.exact("api.example.com")],
                scheduler: ManualNetworkConditionScheduler(), random: FixedNetworkConditionRandomSource(0), now: { clock.now }, route: route
            )
            sessions.perform(.open(duration: 60))
            defer { sessions.end() }
            sut.perform(.setRules([
                NetworkMockRule(name: "Off", isEnabled: false, matcher: .init(path: .exact("/off")), response: .init()),
                NetworkMockRule(name: "Posts", matcher: .init(methods: ["POST"], path: .wildcard("/v1/**")), response: .init(status: 202))
            ]))
            let urls = try ["https://api.example.com/v1/orders", "http://api.example.com/v1/orders", "ftp://api.example.com/v1/orders",
                            "https://other.example.com/v1/orders", "https://api.example.com/off"].map { try #require(URL(string: $0)) }
            let expected = [true, true, false, false, false]

            let posts = urls.map { route.claims(method: "post", url: $0) }
            let get = route.claims(method: "GET", url: urls[0])
            let resolved = route.resolve(method: "POST", url: urls[0])
            clock.set(Self.start.addingTimeInterval(59.999))
            let beforeExpiry = route.claims(method: "POST", url: urls[0])
            clock.set(Self.start.addingTimeInterval(60))
            let atExpiry = route.claims(method: "POST", url: urls[0])

            #expect(posts == expected)
            #expect(!get)
            #expect(resolved?.answer.status == 202)
            #expect(resolved?.answer.ruleName == "Posts")
            #expect(resolved?.answer.headers["Content-Length"] == "0")
            #expect(resolved?.plan == nil)
            #expect(beforeExpiry)
            #expect(!atExpiry)
        }

        @Test("The first matching profile conditions an answer; with none, the answer goes at once")
        func profilesPlanAnswers() throws {
            let clock = MovableClock(Self.start)
            let route = NetworkMockingRoute()
            let sessions = DebugDrawerSessions(maximumDuration: 600, auditCapacity: 100, clock: clock, timer: ManualTimer())
            let sut = NetworkMocking(
                sessions: sessions, allowedHosts: [.domain("example.com")],
                scheduler: ManualNetworkConditionScheduler(), random: FixedNetworkConditionRandomSource(0), now: { clock.now }, route: route
            )
            sessions.perform(.open(duration: 60))
            defer { sessions.end() }
            sut.perform(.setRules([NetworkMockRule(name: "All", matcher: .init(), response: .init())]))
            sut.perform(.setConditions([
                NetworkConditionProfile(name: "Off", isEnabled: false, host: .any, latency: .seconds(9)),
                NetworkConditionProfile(name: "Images", host: .wildcard("img.*.com"), latency: .seconds(1), bandwidth: 500),
                NetworkConditionProfile(name: "Rest", host: .exact("api.example.com"), latency: .seconds(2))
            ]))
            let images = try #require(URL(string: "https://img.example.com/a.png"))
            let api = try #require(URL(string: "https://api.example.com/"))
            let other = try #require(URL(string: "https://www.example.com/"))

            let effects = [images, api, other].map { route.resolve(method: "GET", url: $0)?.plan?.effect }

            #expect(effects == [
                NetworkConditionEffect(profileName: "Images", latency: .seconds(1), bandwidth: 500, failure: nil),
                NetworkConditionEffect(profileName: "Rest", latency: .seconds(2), bandwidth: nil, failure: nil),
                nil
            ])
        }

        @Test("Reset removes every rule and profile, and isActive follows the rules that are on")
        func resetAndIndicator() {
            let clock = MovableClock(Self.start)
            let sessions = DebugDrawerSessions(maximumDuration: 600, auditCapacity: 100, clock: clock, timer: ManualTimer())
            let sut = NetworkMocking(
                sessions: sessions, allowedHosts: [.domain("example.com")],
                scheduler: ManualNetworkConditionScheduler(), random: FixedNetworkConditionRandomSource(0), now: { clock.now },
                route: NetworkMockingRoute()
            )
            sessions.perform(.open(duration: 60))
            defer { sessions.end() }

            sut.perform(.setRules([NetworkMockRule(name: "Off", isEnabled: false, matcher: .init(), response: .init())]))
            let activeWithRuleOff = sut.snapshot.isActive
            sut.perform(.setRules([NetworkMockRule(name: "On", matcher: .init(), response: .init())]))
            sut.perform(.setConditions([NetworkConditionProfile(name: "Slow", latency: .seconds(1))]))
            let activeWithRuleOn = sut.snapshot.isActive
            sut.perform(.reset)

            #expect(!activeWithRuleOff)
            #expect(activeWithRuleOn)
            #expect(sut.snapshot.rules.isEmpty)
            #expect(sut.snapshot.conditions.isEmpty)
            #expect(!sut.snapshot.isActive)
        }

        @Test("The capability refuses file bodies and regular expressions, and takes exact and wildcard patterns")
        func refusals() {
            let commands: [(NetworkMocking.Command, DebugDrawerAuditEntry.Refusal?)] = [
                (.setRules([NetworkMockRule(
                    name: "Exact", matcher: .init(host: .exact("a.example.com"), path: .exact("/")), response: .init()
                )]), nil),
                (.setRules([NetworkMockRule(
                    name: "Wildcard", matcher: .init(host: .wildcard("*.example.com"), path: .wildcard("/**")), response: .init()
                )]), nil),
                (.setRules([NetworkMockRule(name: "Text", matcher: .init(), response: .init(body: .text("{}")))]), nil),
                (.setRules([]), nil),
                (.setRules([NetworkMockRule(name: "Regex host", matcher: .init(host: .regex("a+")), response: .init())]), .malformedCommand),
                (.setRules([NetworkMockRule(name: "Regex path", matcher: .init(path: .regex("/a+")), response: .init())]), .malformedCommand),
                (.setRules([NetworkMockRule(name: "File", matcher: .init(), response: .init(body: .file("a.json")))]), .malformedCommand),
                (.setConditions([NetworkConditionProfile(name: "Wildcard", host: .wildcard("*.example.com"))]), nil),
                (.setConditions([NetworkConditionProfile(name: "Regex", host: .regex(".*"))]), .malformedCommand),
                (.reset, nil)
            ]
            let expected = commands.map { $0.1 }

            let actual = commands.map { NetworkMocking.refusal(for: $0.0) }

            #expect(actual == expected)
        }

        @Test("Two models' rules are both in effect, the newest first, and a model's release takes its own out")
        func routeOwners() throws {
            let clock = MovableClock(Self.start)
            let route = NetworkMockingRoute()
            let sessions = DebugDrawerSessions(maximumDuration: 600, auditCapacity: 100, clock: clock, timer: ManualTimer())
            let url = try #require(URL(string: "https://api.example.com/"))
            let first = NetworkMocking(
                sessions: sessions, allowedHosts: [.domain("example.com")],
                scheduler: ManualNetworkConditionScheduler(), random: FixedNetworkConditionRandomSource(0), now: { clock.now }, route: route
            )
            var second: NetworkMocking? = NetworkMocking(
                sessions: sessions, allowedHosts: [.domain("example.com")],
                scheduler: ManualNetworkConditionScheduler(), random: FixedNetworkConditionRandomSource(0), now: { clock.now }, route: route
            )
            sessions.perform(.open(duration: 60))
            defer { sessions.end() }
            first.perform(.setRules([NetworkMockRule(name: "First", matcher: .init(), response: .init())]))
            second?.perform(.setRules([NetworkMockRule(name: "Second", matcher: .init(), response: .init())]))

            let whileBoth = route.resolve(method: "GET", url: url)?.answer.ruleName
            second = nil
            let afterRelease = route.resolve(method: "GET", url: url)?.answer.ruleName

            #expect(whileBoth == "Second")
            #expect(afterRelease == "First")
        }

        @Test("A snapshot and every command round-trip through JSON")
        func coding() throws {
            let rule = NetworkMockRule(
                id: UUID(uuidString: "3F2B8E1C-0D4A-4B7E-9C61-5A2D7E8F9B10") ?? UUID(),
                name: "Outage", matcher: .init(methods: ["GET"], host: .wildcard("*.example.com")), response: .init(status: 503)
            )
            let profile = NetworkConditionProfile(
                id: UUID(uuidString: "8C4F2A61-7B3D-4E59-A1C8-2D6E9F0B3A47") ?? UUID(), name: "Slow", latency: .milliseconds(1500), bandwidth: 1000
            )
            let snapshot = NetworkMocking.Snapshot(sessionID: UUID(), allowedHosts: [.exact("api.example.com")], rules: [rule], conditions: [profile])
            let commands: [NetworkMocking.Command] = [.setRules([rule]), .setConditions([profile]), .reset]

            let decodedSnapshot = try JSONDecoder().decode(NetworkMocking.Snapshot.self, from: JSONEncoder().encode(snapshot))
            let decodedCommands = try commands.map { try JSONDecoder().decode(NetworkMocking.Command.self, from: JSONEncoder().encode($0)) }

            #expect(decodedSnapshot == snapshot)
            #expect(decodedCommands == commands)
        }
    }
#endif
