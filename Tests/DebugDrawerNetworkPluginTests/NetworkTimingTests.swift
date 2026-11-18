#if DEBUG
    @testable import DebugDrawerNetworkPlugin
    import Foundation
    import Network
    import Testing
    import ViewInspector

    // The request goes through the URL protocol, which reads the process's one set of mock rules,
    // so it is part of the mock interception suite, which is serialized: no other test's rules
    // meet its loopback request. It logs to the shared store, so it waits for its own URL there.
    extension NetworkMockInterceptionTests {
        @Test("A completed request's entry holds its transaction metrics: request, TTFB and response phases, no TLS over plain HTTP")
        func completedRequestHoldsTransactionMetrics() async throws {
            let server = try LoopbackServer()
            defer { server.stop() }
            let port = try await server.start()
            let url = "http://127.0.0.1:\(port)/timing?attempt=\(UUID().uuidString)"
            let logged = NetworkStore.shared.$entries.values

            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [DebugNetworkProtocol.self]
            let session = URLSession(configuration: config)
            let (_, response) = try await session.data(from: #require(URL(string: url)))
            #expect((response as? HTTPURLResponse)?.statusCode == 200)

            var entry: NetworkEntry?
            for await entries in logged {
                if let match = entries.first(where: { $0.url == url && $0.metrics != nil }) {
                    entry = match
                    break
                }
            }
            let metrics = try #require(entry?.metrics)
            let kinds = metrics.phases.map(\.kind)
            #expect(kinds.contains(.request), "phases: \(kinds)")
            #expect(kinds.contains(.timeToFirstByte), "phases: \(kinds)")
            #expect(kinds.contains(.response), "phases: \(kinds)")
            #expect(!kinds.contains(.tls), "plain HTTP has no TLS phase")
            #expect(metrics.protocolName == "http/1.1")
            #expect(!metrics.isCacheHit)
            #expect(metrics.total > 0)
        }
    }

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct NetworkTimingTests {
        // MARK: Phase computation

        @Test("Phases come from the timestamps, with Connect ending where TLS starts")
        func phasesFromTimestampsSplitConnectAtTLSStart() {
            let t0 = Date(timeIntervalSinceReferenceDate: 1000)
            let metrics = NetworkTimingMetrics(
                timestamps: .init(
                    fetchStart: t0,
                    domainLookupStart: t0, domainLookupEnd: t0 + 0.010,
                    connectStart: t0 + 0.010, secureConnectionStart: t0 + 0.030,
                    secureConnectionEnd: t0 + 0.060, connectEnd: t0 + 0.060,
                    requestStart: t0 + 0.060, requestEnd: t0 + 0.061,
                    responseStart: t0 + 0.200, responseEnd: t0 + 0.250
                ),
                protocolName: "h2", isReusedConnection: false, isCacheHit: false
            )
            #expect(metrics.phases.map(\.kind) == NetworkTimingMetrics.Phase.Kind.allCases)
            let connect = metrics.phases[1]
            #expect(abs(connect.start - 0.010) <= 1e-6)
            #expect(abs(connect.duration - 0.020) <= 1e-6)
            let ttfb = metrics.phases[4]
            #expect(abs(ttfb.duration - 0.139) <= 1e-6)
            #expect(abs(metrics.total - 0.250) <= 1e-6)
        }

        @Test("A reused connection has no DNS, Connect or TLS phases")
        func reusedConnectionHasNoDNSConnectOrTLSPhases() {
            let t0 = Date(timeIntervalSinceReferenceDate: 1000)
            let metrics = NetworkTimingMetrics(
                timestamps: .init(
                    fetchStart: t0,
                    requestStart: t0 + 0.001, requestEnd: t0 + 0.002,
                    responseStart: t0 + 0.050, responseEnd: t0 + 0.060
                ),
                protocolName: "h2", isReusedConnection: true, isCacheHit: false
            )
            #expect(metrics.phases.map(\.kind) == [.request, .timeToFirstByte, .response])
        }

        // MARK: View

        @Test("The detail shows each reported phase with its duration, and the protocol, reuse and cache facts")
        func detailShowsEachReportedPhaseAndConnectionFacts() throws {
            let t0 = Date(timeIntervalSinceReferenceDate: 1000)
            let metrics = NetworkTimingMetrics(
                timestamps: .init(
                    fetchStart: t0,
                    domainLookupStart: t0, domainLookupEnd: t0 + 0.010,
                    connectStart: t0 + 0.010, secureConnectionStart: t0 + 0.030,
                    secureConnectionEnd: t0 + 0.060, connectEnd: t0 + 0.060,
                    requestStart: t0 + 0.060, requestEnd: t0 + 0.061,
                    responseStart: t0 + 0.200, responseEnd: t0 + 0.250
                ),
                protocolName: "h2", isReusedConnection: true, isCacheHit: false
            )
            let texts = try texts(in: NetworkTimingView(metrics: metrics))
            for label in ["DNS", "Connect", "TLS", "Request", "TTFB", "Response"] {
                #expect(texts.contains(label), "missing \(label) in \(texts)")
            }
            #expect(texts.contains("139.0ms"), "TTFB duration missing in \(texts)")
            #expect(texts.contains("Protocol"))
            #expect(texts.contains("h2"))
            #expect(texts.contains("Reused"))
            #expect(texts.contains("Yes"))
            #expect(texts.contains("Cache hit"))
            #expect(texts.contains("No"))
        }

        @Test("The detail leaves out the phases with no interval, and shows a dash for an unknown protocol")
        func detailOmitsPhasesWithNilIntervals() throws {
            let t0 = Date(timeIntervalSinceReferenceDate: 1000)
            let metrics = NetworkTimingMetrics(
                timestamps: .init(
                    fetchStart: t0,
                    requestStart: t0 + 0.001, requestEnd: t0 + 0.002,
                    responseStart: t0 + 0.050, responseEnd: t0 + 0.060
                ),
                protocolName: nil, isReusedConnection: false, isCacheHit: true
            )
            let texts = try texts(in: NetworkTimingView(metrics: metrics))
            #expect(!texts.contains("DNS"))
            #expect(!texts.contains("Connect"))
            #expect(!texts.contains("TLS"))
            #expect(texts.contains("Request"))
            #expect(texts.contains("TTFB"))
            #expect(texts.contains("Response"))
            #expect(texts.contains("—"))
            #expect(texts.contains("Yes"))
        }

        private func texts(in view: NetworkTimingView) throws -> [String] {
            try view.inspect().findAll(ViewType.Text.self).map { try $0.string() }
        }
    }

    // MARK: - Loopback HTTP server

    /// Answers every connection with one small HTTP/1.1 200 response, then closes it.
    private final class LoopbackServer: @unchecked Sendable {
        private let listener: NWListener
        private let queue = DispatchQueue(label: "LoopbackServer")

        init() throws {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
            listener = try NWListener(using: parameters)
        }

        func start() async throws -> UInt16 {
            listener.newConnectionHandler = { [queue] connection in
                connection.start(queue: queue)
                connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { _, _, _, _ in
                    let body = #"{"ok":true}"#
                    let response = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n"
                        + "Content-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
                    connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
                        connection.cancel()
                    })
                }
            }
            return try await withCheckedThrowingContinuation { continuation in
                let once = Once()
                listener.stateUpdateHandler = { [listener] state in
                    switch state {
                    case .ready:
                        if let port = listener.port?.rawValue, once.claim() { continuation.resume(returning: port) }
                    case let .failed(error):
                        if once.claim() { continuation.resume(throwing: error) }
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

        /// stateUpdateHandler runs on `queue`, so a plain flag is enough.
        private final class Once: @unchecked Sendable {
            private var claimed = false
            func claim() -> Bool {
                defer { claimed = true }
                return !claimed
            }
        }
    }
#endif
