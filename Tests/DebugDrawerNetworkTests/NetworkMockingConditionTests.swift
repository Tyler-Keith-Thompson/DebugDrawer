// Conditioning as a real URLSession meets it: the session's rules answer through
// NetworkMockingURLProtocol, and a profile delays, paces or fails the answer on a scheduler the test
// advances by hand, so no test waits on the clock. The session is opened and the rules set on the
// models directly; NetworkMockingSidecarTests covers the receiver's gating. These requests go
// through the process's one route, so they are part of that serialized suite.
#if DEBUG
    import DebugDrawer
    @testable import DebugDrawerNetwork
    @testable import DebugDrawerReceiver
    import Foundation
    import Testing

    extension NetworkMockingSidecarTests {
        @Test("A profile's latency holds a mocked answer until the scheduler reaches it")
        func latencyDelaysTheAnswer() async throws {
            let clock = MovableClock(Date(timeIntervalSince1970: 1_778_307_200))
            let scheduler = ManualNetworkConditionScheduler()
            let sessions = DebugDrawerSessions(maximumDuration: 600, auditCapacity: 100, clock: clock, timer: ManualTimer())
            let mocking = NetworkMocking(
                sessions: sessions, allowedHosts: [.exact("127.0.0.1")],
                scheduler: scheduler, random: FixedNetworkConditionRandomSource(0), now: { clock.now }, route: .shared
            )
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [NetworkMockingURLProtocol.self] + (configuration.protocolClasses ?? [])
            let urlSession = URLSession(configuration: configuration)
            defer { urlSession.invalidateAndCancel() }
            // Nothing listens on the discard port: only the rule can answer.
            let url = try #require(URL(string: "http://127.0.0.1:9/v1/slow"))
            sessions.perform(.open(duration: 60))
            defer { sessions.end() }
            mocking.perform(.setRules([NetworkMockRule(
                name: "Slow", matcher: .init(host: .exact("127.0.0.1")), response: .init(body: .text("mocked"))
            )]))
            mocking.perform(.setConditions([NetworkConditionProfile(name: "Two seconds", host: .exact("127.0.0.1"), latency: .seconds(2))]))
            let expectedDelays: [Duration] = [.seconds(2)]

            let request = Task { try await urlSession.data(from: url) }
            await scheduler.waitUntil { $0.pendingCount == 1 }
            let delays = scheduler.snapshot.delays
            scheduler.advance(by: .seconds(2))
            let (data, _) = try await request.value

            #expect(delays == expectedDelays)
            #expect(String(bytes: data, encoding: .utf8) == "mocked")
        }

        @Test("A profile's bandwidth delivers a mocked body in timed parts")
        func bandwidthPacesTheBody() async throws {
            let clock = MovableClock(Date(timeIntervalSince1970: 1_778_307_200))
            let scheduler = ManualNetworkConditionScheduler()
            let sessions = DebugDrawerSessions(maximumDuration: 600, auditCapacity: 100, clock: clock, timer: ManualTimer())
            let mocking = NetworkMocking(
                sessions: sessions, allowedHosts: [.exact("127.0.0.1")],
                scheduler: scheduler, random: FixedNetworkConditionRandomSource(0), now: { clock.now }, route: .shared
            )
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [NetworkMockingURLProtocol.self] + (configuration.protocolClasses ?? [])
            let urlSession = URLSession(configuration: configuration)
            defer { urlSession.invalidateAndCancel() }
            let url = try #require(URL(string: "http://127.0.0.1:9/v1/report"))
            let body = String(repeating: "0123456789", count: 3)
            sessions.perform(.open(duration: 60))
            defer { sessions.end() }
            mocking.perform(.setRules([NetworkMockRule(
                name: "Report", matcher: .init(host: .exact("127.0.0.1")), response: .init(body: .text(body))
            )]))
            mocking.perform(.setConditions([NetworkConditionProfile(name: "Ten bytes a second", host: .any, bandwidth: 10)]))
            // Ten parts a second at the cap, of one byte each.
            let expectedDelays = Array(repeating: Duration.milliseconds(100), count: 30)

            let request = Task { try await urlSession.data(from: url) }
            await scheduler.waitUntil { $0.pendingCount == 1 }
            scheduler.advance(by: .seconds(3))
            let (data, _) = try await request.value

            #expect(String(bytes: data, encoding: .utf8) == body)
            #expect(scheduler.snapshot.delays == expectedDelays)
        }

        @Test("A profile that always fails ends a mocked request as its failure says", arguments: NetworkConditionProfile.Failure.allCases)
        func failureInjected(_ failure: NetworkConditionProfile.Failure) async throws {
            let clock = MovableClock(Date(timeIntervalSince1970: 1_778_307_200))
            let sessions = DebugDrawerSessions(maximumDuration: 600, auditCapacity: 100, clock: clock, timer: ManualTimer())
            let mocking = NetworkMocking(
                sessions: sessions, allowedHosts: [.exact("127.0.0.1")],
                scheduler: ManualNetworkConditionScheduler(), random: FixedNetworkConditionRandomSource(0), now: { clock.now }, route: .shared
            )
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [NetworkMockingURLProtocol.self] + (configuration.protocolClasses ?? [])
            let urlSession = URLSession(configuration: configuration)
            defer { urlSession.invalidateAndCancel() }
            let url = try #require(URL(string: "http://127.0.0.1:9/v1/orders"))
            sessions.perform(.open(duration: 60))
            defer { sessions.end() }
            mocking.perform(.setRules([NetworkMockRule(
                name: "Orders", matcher: .init(host: .exact("127.0.0.1")), response: .init(body: .text("mocked"))
            )]))
            mocking.perform(.setConditions([NetworkConditionProfile(name: "Down", host: .any, failureRate: 100, failure: failure)]))
            let expected = switch failure {
            case .timedOut: "error \(URLError.Code.timedOut.rawValue)"
            case .notConnectedToInternet: "error \(URLError.Code.notConnectedToInternet.rawValue)"
            case .internalServerError: "status 500, 0 bytes"
            }

            let actual: String
            do {
                let (data, response) = try await urlSession.data(from: url)
                actual = "status \((response as? HTTPURLResponse)?.statusCode ?? 0), \(data.count) bytes"
            } catch let error as URLError {
                actual = "error \(error.code.rawValue)"
            }

            #expect(actual == expected)
        }

        @Test("A profile below 100 percent fails the requests whose roll is under its rate, and lets the others through")
        func failureRateRolls() async throws {
            let clock = MovableClock(Date(timeIntervalSince1970: 1_778_307_200))
            let sessions = DebugDrawerSessions(maximumDuration: 600, auditCapacity: 100, clock: clock, timer: ManualTimer())
            let mocking = NetworkMocking(
                sessions: sessions, allowedHosts: [.exact("127.0.0.1")],
                scheduler: ManualNetworkConditionScheduler(), random: FixedNetworkConditionRandomSource(10, 90), now: { clock.now }, route: .shared
            )
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [NetworkMockingURLProtocol.self] + (configuration.protocolClasses ?? [])
            let urlSession = URLSession(configuration: configuration)
            defer { urlSession.invalidateAndCancel() }
            let url = try #require(URL(string: "http://127.0.0.1:9/v1/orders"))
            sessions.perform(.open(duration: 60))
            defer { sessions.end() }
            mocking.perform(.setRules([NetworkMockRule(
                name: "Orders", matcher: .init(host: .exact("127.0.0.1")), response: .init(body: .text("mocked"))
            )]))
            mocking.perform(.setConditions([NetworkConditionProfile(name: "Lossy", host: .any, failureRate: 50, failure: .notConnectedToInternet)]))
            let expected = ["error \(URLError.Code.notConnectedToInternet.rawValue)", "mocked"]

            var actual: [String] = []
            for _ in 0 ..< 2 {
                do {
                    let (data, _) = try await urlSession.data(from: url)
                    actual.append(String(bytes: data, encoding: .utf8) ?? "")
                } catch let error as URLError {
                    actual.append("error \(error.code.rawValue)")
                }
            }

            #expect(actual == expected)
        }

        @Test("A profile conditions only the answers rules give: a request no rule answers reaches the server at once, unconditioned")
        func conditionsOnlyMockedAnswers() async throws {
            let clock = MovableClock(Date(timeIntervalSince1970: 1_778_307_200))
            let scheduler = ManualNetworkConditionScheduler()
            let sessions = DebugDrawerSessions(maximumDuration: 600, auditCapacity: 100, clock: clock, timer: ManualTimer())
            let mocking = NetworkMocking(
                sessions: sessions, allowedHosts: [.exact("127.0.0.1")],
                scheduler: scheduler, random: FixedNetworkConditionRandomSource(0), now: { clock.now }, route: .shared
            )
            let server = try ScriptedServer { _ in "HTTP/1.1 200 OK\r\nContent-Length: 6\r\nConnection: close\r\n\r\nserver" }
            defer { server.stop() }
            let port = try await server.start()
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [NetworkMockingURLProtocol.self] + (configuration.protocolClasses ?? [])
            let urlSession = URLSession(configuration: configuration)
            defer { urlSession.invalidateAndCancel() }
            let unmocked = try #require(URL(string: "http://127.0.0.1:\(port)/v1/profile"))
            sessions.perform(.open(duration: 60))
            defer { sessions.end() }
            mocking.perform(.setRules([NetworkMockRule(
                name: "Orders", matcher: .init(host: .exact("127.0.0.1"), path: .exact("/v1/orders")), response: .init()
            )]))
            mocking.perform(.setConditions([NetworkConditionProfile(name: "Slow", host: .any, latency: .seconds(5), failureRate: 100)]))

            let (data, _) = try await urlSession.data(from: unmocked)

            #expect(String(bytes: data, encoding: .utf8) == "server")
            #expect(scheduler.snapshot.delays.isEmpty)
            #expect(server.requests.map(\.path) == ["/v1/profile"])
        }
    }
#endif
