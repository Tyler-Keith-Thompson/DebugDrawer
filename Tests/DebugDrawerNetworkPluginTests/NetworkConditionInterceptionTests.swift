#if DEBUG
    @testable import DebugDrawerNetworkPlugin
    import Foundation
    import Network
    import os
    import Testing

    // These requests go through the URL protocol, which reads the process's one set of mock rules
    // and conditions, so they are part of the mock interception suite, which is serialized: no
    // two of its tests change the rules or the conditions at once. Each test conditions requests on
    // a scheduler it advances by hand, so a latency is waited out by the test, not by the clock;
    // mock rules answer the `.invalid` hosts, which never resolve, so a request that reached the
    // network would fail.
    extension NetworkMockInterceptionTests {
        @Test("A request to a conditioned host waits for the latency; a request to another host is answered at once")
        func conditionedHostWaits() async throws {
            let scheduler = ManualNetworkConditionScheduler()
            NetworkMockRules.shared.activate([
                NetworkMockRule(name: "Slow API", matcher: .init(host: .exact("slow.invalid")), response: .init(status: 200, body: .text("slow"))),
                NetworkMockRule(name: "Fast API", matcher: .init(host: .exact("fast.invalid")), response: .init(status: 200, body: .text("fast")))
            ]) { _ in nil }
            NetworkConditions.shared.activate(
                [NetworkConditionProfile(name: "Slow", host: .exact("slow.invalid"), latency: .milliseconds(2000))],
                scheduler: scheduler, random: FixedNetworkConditionRandomSource(0)
            )
            defer {
                NetworkMockRules.shared.activate([]) { _ in nil }
                NetworkConditions.shared.activate([], scheduler: scheduler, random: FixedNetworkConditionRandomSource(0))
            }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [DebugNetworkProtocol.self]
            let session = URLSession(configuration: configuration)
            let slowURL = try #require(URL(string: "https://slow.invalid/\(UUID().uuidString)"))
            let fastURL = try #require(URL(string: "https://fast.invalid/\(UUID().uuidString)"))
            let slow = Task { try await session.data(from: slowURL) }

            await scheduler.waitUntil { $0.pendingCount == 1 }
            let (fastData, _) = try await session.data(from: fastURL)
            let scheduledBeforeFast = scheduler.snapshot.delays
            scheduler.advance(by: .milliseconds(1999))
            let pendingBeforeLatency = scheduler.snapshot.pendingCount
            scheduler.advance(by: .milliseconds(1))
            let (slowData, slowResponse) = try await slow.value

            #expect(fastData == Data("fast".utf8))
            #expect(scheduledBeforeFast == [.milliseconds(2000)])
            #expect(pendingBeforeLatency == 1)
            #expect((slowResponse as? HTTPURLResponse)?.statusCode == 200)
            #expect(slowData == Data("slow".utf8))
        }

        @Test("On the real scheduler, a 200 ms latency holds the answer back at least 200 ms")
        func realSchedulerWaits() async throws {
            let latency = Duration.milliseconds(200)
            NetworkMockRules.shared.activate([
                NetworkMockRule(name: "Timed", matcher: .init(host: .exact("timed.invalid")), response: .init(status: 200, body: .text("timed")))
            ]) { _ in nil }
            NetworkConditions.shared.activate(
                [NetworkConditionProfile(name: "Timed", host: .exact("timed.invalid"), latency: latency)],
                scheduler: _NetworkConditionScheduler(), random: FixedNetworkConditionRandomSource(0)
            )
            defer {
                NetworkMockRules.shared.activate([]) { _ in nil }
                NetworkConditions.shared.activate([], scheduler: _NetworkConditionScheduler(), random: FixedNetworkConditionRandomSource(0))
            }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [DebugNetworkProtocol.self]
            let session = URLSession(configuration: configuration)
            let url = try #require(URL(string: "https://timed.invalid/\(UUID().uuidString)"))
            let clock = ContinuousClock()
            let start = clock.now

            let (data, _) = try await session.data(from: url)

            let elapsed = clock.now - start
            #expect(data == Data("timed".utf8))
            #expect(elapsed >= latency)
        }

        @Test(
            "A profile that fails every request fails it with its error's code: NSURLErrorTimedOut or NSURLErrorNotConnectedToInternet",
            arguments: [(NetworkConditionProfile.Failure.timedOut, NSURLErrorTimedOut), (.notConnectedToInternet, NSURLErrorNotConnectedToInternet)]
        )
        func failsWithError(failure: NetworkConditionProfile.Failure, expectedCode: Int) async throws {
            let scheduler = ManualNetworkConditionScheduler()
            NetworkMockRules.shared.activate([
                NetworkMockRule(name: "Answer", matcher: .init(host: .exact("down.invalid")), response: .init(status: 200))
            ]) { _ in nil }
            NetworkConditions.shared.activate(
                [NetworkConditionProfile(name: "Down", host: .exact("down.invalid"), failureRate: 100, failure: failure)],
                scheduler: scheduler, random: FixedNetworkConditionRandomSource(99)
            )
            defer {
                NetworkMockRules.shared.activate([]) { _ in nil }
                NetworkConditions.shared.activate([], scheduler: scheduler, random: FixedNetworkConditionRandomSource(0))
            }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [DebugNetworkProtocol.self]
            let session = URLSession(configuration: configuration)
            let url = try #require(URL(string: "https://down.invalid/\(UUID().uuidString)"))

            let error = await #expect(throws: URLError.self) { try await session.data(from: url) }

            #expect(error?.errorCode == expectedCode)
        }

        @Test("A profile that fails every request with HTTP 500 answers status 500 with an empty body, whatever the mock says")
        func failsWithServerError() async throws {
            let scheduler = ManualNetworkConditionScheduler()
            NetworkMockRules.shared.activate([
                NetworkMockRule(name: "Answer", matcher: .init(host: .exact("broken.invalid")), response: .init(status: 200, body: .text("fine")))
            ]) { _ in nil }
            NetworkConditions.shared.activate(
                [NetworkConditionProfile(name: "Broken", host: .exact("broken.invalid"), failureRate: 100, failure: .internalServerError)],
                scheduler: scheduler, random: FixedNetworkConditionRandomSource(99)
            )
            defer {
                NetworkMockRules.shared.activate([]) { _ in nil }
                NetworkConditions.shared.activate([], scheduler: scheduler, random: FixedNetworkConditionRandomSource(0))
            }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [DebugNetworkProtocol.self]
            let session = URLSession(configuration: configuration)
            let url = try #require(URL(string: "https://broken.invalid/\(UUID().uuidString)"))

            let (data, response) = try await session.data(from: url)

            #expect((response as? HTTPURLResponse)?.statusCode == 500)
            #expect(data.isEmpty)
        }

        @Test("Turning the profile off makes the next request to its host complete with no latency and no failure")
        func disablingRestores() async throws {
            let scheduler = ManualNetworkConditionScheduler()
            let model = NetworkConditionsModel(
                storage: FakeNetworkConditionStorage(), active: .shared, scheduler: scheduler, random: FixedNetworkConditionRandomSource(99)
            )
            let profile = NetworkConditionProfile(
                name: "Down", host: .exact("toggle.invalid"), latency: .seconds(5), failureRate: 100, failure: .timedOut
            )
            NetworkMockRules.shared.activate([
                NetworkMockRule(name: "Answer", matcher: .init(host: .exact("toggle.invalid")), response: .init(status: 200, body: .text("ok")))
            ]) { _ in nil }
            model.save(profile)
            defer {
                NetworkMockRules.shared.activate([]) { _ in nil }
                NetworkConditions.shared.activate([], scheduler: scheduler, random: FixedNetworkConditionRandomSource(0))
            }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [DebugNetworkProtocol.self]
            let session = URLSession(configuration: configuration)
            let firstURL = try #require(URL(string: "https://toggle.invalid/first"))
            let secondURL = try #require(URL(string: "https://toggle.invalid/second"))
            let first = Task { try await session.data(from: firstURL) }
            await scheduler.waitUntil { $0.pendingCount == 1 }
            scheduler.advance(by: .seconds(5))
            let firstError = await #expect(throws: URLError.self) { try await first.value }

            model.setEnabled(false, id: profile.id)
            let (data, response) = try await session.data(from: secondURL)

            #expect(firstError?.code == .timedOut)
            #expect((response as? HTTPURLResponse)?.statusCode == 200)
            #expect(data == Data("ok".utf8))
            #expect(scheduler.snapshot.delays == [.seconds(5)])
        }

        @Test("The latency comes first: a real request reaches the server only once it is waited out")
        func latencyBeforeNetwork() async throws {
            let server = try CountingServer(body: Data("from the server".utf8))
            defer { server.stop() }
            let port = try await server.start()
            let scheduler = ManualNetworkConditionScheduler()
            NetworkConditions.shared.activate(
                [NetworkConditionProfile(name: "Slow loopback", host: .exact("localhost"), latency: .seconds(1))],
                scheduler: scheduler, random: FixedNetworkConditionRandomSource(0)
            )
            defer { NetworkConditions.shared.activate([], scheduler: scheduler, random: FixedNetworkConditionRandomSource(0)) }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [DebugNetworkProtocol.self]
            let session = URLSession(configuration: configuration)
            let url = try #require(URL(string: "http://localhost:\(port)/slow"))
            let request = Task { try await session.data(from: url) }

            await scheduler.waitUntil { $0.pendingCount == 1 }
            let arrivedDuringLatency = server.requestCount
            scheduler.advance(by: .seconds(1))
            let (data, response) = try await request.value

            #expect(arrivedDuringLatency == 0)
            #expect(server.requestCount == 1)
            #expect((response as? HTTPURLResponse)?.statusCode == 200)
            #expect(data == Data("from the server".utf8))
        }

        @Test("A real response under a cap is read whole, then delivered in parts at the cap: 1,500 bytes at 1,000 B/s in 15 parts")
        func bandwidthOverRealResponse() async throws {
            let body = Data(repeating: 42, count: 1500)
            let server = try CountingServer(body: body)
            defer { server.stop() }
            let port = try await server.start()
            let scheduler = ManualNetworkConditionScheduler()
            NetworkConditions.shared.activate(
                [NetworkConditionProfile(name: "Narrow loopback", host: .exact("localhost"), bandwidth: 1000)],
                scheduler: scheduler, random: FixedNetworkConditionRandomSource(0)
            )
            defer { NetworkConditions.shared.activate([], scheduler: scheduler, random: FixedNetworkConditionRandomSource(0)) }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [DebugNetworkProtocol.self]
            let session = URLSession(configuration: configuration)
            let url = try #require(URL(string: "http://localhost:\(port)/narrow"))
            let request = Task { try await session.data(from: url) }

            await scheduler.waitUntil { $0.pendingCount == 1 }
            scheduler.advance(by: .milliseconds(1499))
            let pendingBeforeEnd = scheduler.snapshot.pendingCount
            scheduler.advance(by: .milliseconds(1))
            let (data, _) = try await request.value

            #expect(pendingBeforeEnd == 1)
            #expect(data == body)
            #expect(scheduler.snapshot.delays == Array(repeating: .milliseconds(100), count: 15))
        }

        @Test("Cancelling a request during its latency cancels the scheduled step")
        func cancelDuringLatency() async throws {
            let scheduler = ManualNetworkConditionScheduler()
            NetworkMockRules.shared.activate([
                NetworkMockRule(name: "Answer", matcher: .init(host: .exact("cancel.invalid")), response: .init(status: 200))
            ]) { _ in nil }
            NetworkConditions.shared.activate(
                [NetworkConditionProfile(name: "Slow", host: .exact("cancel.invalid"), latency: .seconds(10))],
                scheduler: scheduler, random: FixedNetworkConditionRandomSource(0)
            )
            defer {
                NetworkMockRules.shared.activate([]) { _ in nil }
                NetworkConditions.shared.activate([], scheduler: scheduler, random: FixedNetworkConditionRandomSource(0))
            }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [DebugNetworkProtocol.self]
            let session = URLSession(configuration: configuration)
            let url = try #require(URL(string: "https://cancel.invalid/\(UUID().uuidString)"))
            let request = Task { try await session.data(from: url) }
            await scheduler.waitUntil { $0.pendingCount == 1 }

            request.cancel()
            let error = await #expect(throws: URLError.self) { try await request.value }
            await scheduler.waitUntil { $0.cancelledCount == 1 }
            scheduler.advance(by: .seconds(10))

            #expect(error?.code == .cancelled)
            #expect(scheduler.snapshot.pendingCount == 0)
        }

        @Test("The log marks a conditioned request with the profile and what it did: delayed and mocked, or failed")
        func marksConditionedLogEntry() async throws {
            let scheduler = ManualNetworkConditionScheduler()
            NetworkMockRules.shared.activate([
                NetworkMockRule(name: "Greeting", matcher: .init(host: .exact("logged.invalid")), response: .init(status: 200, body: .text("hi")))
            ]) { _ in nil }
            NetworkConditions.shared.activate(
                [
                    NetworkConditionProfile(
                        name: "Offline", host: .exact("logged.invalid"), latency: .milliseconds(300), failureRate: 50, failure: .timedOut
                    )
                ],
                scheduler: scheduler, random: FixedNetworkConditionRandomSource(90, 10)
            )
            defer {
                NetworkMockRules.shared.activate([]) { _ in nil }
                NetworkConditions.shared.activate([], scheduler: scheduler, random: FixedNetworkConditionRandomSource(0))
            }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [DebugNetworkProtocol.self]
            let session = URLSession(configuration: configuration)
            let passedAddress = "https://logged.invalid/passed?id=\(UUID().uuidString)"
            let failedAddress = "https://logged.invalid/failed?id=\(UUID().uuidString)"
            let passedURL = try #require(URL(string: passedAddress))
            let failedURL = try #require(URL(string: failedAddress))
            let logged = NetworkStore.shared.$entries.values

            let passed = Task { try await session.data(from: passedURL) }
            await scheduler.waitUntil { $0.pendingCount == 1 }
            scheduler.advance(by: .milliseconds(300))
            _ = try await passed.value
            let failed = Task { try await session.data(from: failedURL) }
            await scheduler.waitUntil { $0.delays.count == 2 && $0.pendingCount == 1 }
            scheduler.advance(by: .milliseconds(300))
            _ = await #expect(throws: URLError.self) { try await failed.value }

            var passedEntry: NetworkEntry?
            var failedEntry: NetworkEntry?
            for await entries in logged {
                passedEntry = entries.first { $0.url == passedAddress && $0.isComplete }
                failedEntry = entries.first { $0.url == failedAddress && $0.isComplete }
                if passedEntry != nil, failedEntry != nil { break }
            }
            let actualPassed = try #require(passedEntry)
            let actualFailed = try #require(failedEntry)
            #expect(actualPassed.conditionEffect?.profileName == "Offline")
            #expect(actualPassed.conditionEffect?.summary == "Delayed 300 ms")
            #expect(actualPassed.mockRuleName == "Greeting")
            #expect(actualPassed.statusCode == 200)
            #expect(actualPassed.responseBody == Data("hi".utf8))
            #expect(actualFailed.conditionEffect?.summary == "Delayed 300 ms · Failed: timeout")
            #expect(actualFailed.mockRuleName == nil)
            #expect(actualFailed.error != nil)
            #expect(actualFailed.isFailure)
        }
    }

    // MARK: - Counting loopback server

    /// Answers every request with one HTTP/1.1 200 response carrying `body`, counting the requests
    /// it read. Listens on the loopback address, which `localhost` reaches.
    private final class CountingServer: Sendable {
        private let listener: NWListener
        private let body: Data
        private let queue = DispatchQueue(label: "CountingServer")
        private let count = OSAllocatedUnfairLock(initialState: 0)

        init(body: Data) throws {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
            listener = try NWListener(using: parameters)
            self.body = body
        }

        /// How many requests have arrived, whole.
        var requestCount: Int {
            count.withLock { $0 }
        }

        func start() async throws -> UInt16 {
            listener.newConnectionHandler = { [queue, count, body] connection in
                connection.start(queue: queue)
                Self.read(connection, buffer: Data()) {
                    count.withLock { $0 += 1 }
                    let head = "HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\n"
                        + "Content-Length: \(body.count)\r\nConnection: close\r\n\r\n"
                    connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in
                        connection.cancel()
                    })
                }
            }
            return try await withCheckedThrowingContinuation { continuation in
                let resumed = OSAllocatedUnfairLock(initialState: false)
                listener.stateUpdateHandler = { [listener] state in
                    let claim = { resumed.withLock { wasResumed in
                        defer { wasResumed = true }
                        return !wasResumed
                    } }
                    switch state {
                    case .ready:
                        if let port = listener.port?.rawValue, claim() { continuation.resume(returning: port) }
                    case let .failed(error):
                        if claim() { continuation.resume(throwing: error) }
                    default:
                        break
                    }
                }
                listener.start(queue: queue)
            }
        }

        func stop() {
            listener.cancel()
        }

        /// Reads until the end of the request's headers; the tests send GETs, with no body.
        private static func read(_ connection: NWConnection, buffer: Data, completion: @escaping @Sendable () -> Void) {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { chunk, _, isComplete, error in
                var buffer = buffer
                if let chunk { buffer.append(chunk) }
                if buffer.range(of: Data("\r\n\r\n".utf8)) != nil {
                    completion()
                } else if !isComplete, error == nil {
                    read(connection, buffer: buffer, completion: completion)
                }
            }
        }
    }
#endif
