#if DEBUG
    import Combine
    @testable import DebugDrawerNetworkPlugin
    import Network
    import ViewInspector
    import XCTest

    @MainActor
    final class NetworkTimingTests: XCTestCase {
        // MARK: Capture

        func testCompletedRequestHoldsTransactionMetrics() async throws {
            let server = try LoopbackServer()
            defer { server.stop() }
            let port = try await server.start()

            let store = NetworkStore.shared
            store.clear()
            let url = "http://127.0.0.1:\(port)/timing"

            let captured = expectation(description: "entry has metrics")
            var entry: NetworkEntry?
            let cancellable = store.$entries.sink { entries in
                if let match = entries.first(where: { $0.url == url && $0.metrics != nil }), entry == nil {
                    entry = match
                    captured.fulfill()
                }
            }
            defer { cancellable.cancel() }

            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [DebugNetworkProtocol.self]
            let session = URLSession(configuration: config)
            let (_, response) = try await session.data(from: XCTUnwrap(URL(string: url)))
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)

            await fulfillment(of: [captured], timeout: 10)
            let metrics = try XCTUnwrap(entry?.metrics)
            let kinds = metrics.phases.map(\.kind)
            XCTAssertTrue(kinds.contains(.request), "phases: \(kinds)")
            XCTAssertTrue(kinds.contains(.timeToFirstByte), "phases: \(kinds)")
            XCTAssertTrue(kinds.contains(.response), "phases: \(kinds)")
            XCTAssertFalse(kinds.contains(.tls), "plain HTTP has no TLS phase")
            XCTAssertEqual(metrics.protocolName, "http/1.1")
            XCTAssertFalse(metrics.isCacheHit)
            XCTAssertGreaterThan(metrics.total, 0)
        }

        // MARK: Phase computation

        func testPhasesFromTimestampsSplitConnectAtTLSStart() {
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
            XCTAssertEqual(metrics.phases.map(\.kind), NetworkTimingMetrics.Phase.Kind.allCases)
            let connect = metrics.phases[1]
            XCTAssertEqual(connect.start, 0.010, accuracy: 1e-6)
            XCTAssertEqual(connect.duration, 0.020, accuracy: 1e-6)
            let ttfb = metrics.phases[4]
            XCTAssertEqual(ttfb.duration, 0.139, accuracy: 1e-6)
            XCTAssertEqual(metrics.total, 0.250, accuracy: 1e-6)
        }

        func testReusedConnectionHasNoDNSConnectOrTLSPhases() {
            let t0 = Date(timeIntervalSinceReferenceDate: 1000)
            let metrics = NetworkTimingMetrics(
                timestamps: .init(
                    fetchStart: t0,
                    requestStart: t0 + 0.001, requestEnd: t0 + 0.002,
                    responseStart: t0 + 0.050, responseEnd: t0 + 0.060
                ),
                protocolName: "h2", isReusedConnection: true, isCacheHit: false
            )
            XCTAssertEqual(metrics.phases.map(\.kind), [.request, .timeToFirstByte, .response])
        }

        // MARK: View

        func testDetailShowsEachReportedPhaseAndConnectionFacts() throws {
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
                XCTAssertTrue(texts.contains(label), "missing \(label) in \(texts)")
            }
            XCTAssertTrue(texts.contains("139.0ms"), "TTFB duration missing in \(texts)")
            XCTAssertTrue(texts.contains("Protocol"))
            XCTAssertTrue(texts.contains("h2"))
            XCTAssertTrue(texts.contains("Reused"))
            XCTAssertTrue(texts.contains("Yes"))
            XCTAssertTrue(texts.contains("Cache hit"))
            XCTAssertTrue(texts.contains("No"))
        }

        func testDetailOmitsPhasesWithNilIntervals() throws {
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
            XCTAssertFalse(texts.contains("DNS"))
            XCTAssertFalse(texts.contains("Connect"))
            XCTAssertFalse(texts.contains("TLS"))
            XCTAssertTrue(texts.contains("Request"))
            XCTAssertTrue(texts.contains("TTFB"))
            XCTAssertTrue(texts.contains("Response"))
            XCTAssertTrue(texts.contains("—"))
            XCTAssertTrue(texts.contains("Yes"))
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
