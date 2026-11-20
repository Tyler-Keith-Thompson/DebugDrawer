// The README's "Diagnostics capture in production" example, verbatim, so the README cannot drift
// from the code: the app's setup, its logger's line and its networking code's record. The request
// goes to a URL protocol of the test's own, listed only in the session the test makes, so nothing
// reaches the network.
import DebugDrawerReceiver
import Foundation
import Testing

/// Answers every request with a JSON body, standing in for the app's server.
private final class StubServer: URLProtocol, @unchecked Sendable {
    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let response = HTTPURLResponse(url: url, statusCode: 402, httpVersion: "HTTP/1.1", headerFields: nil) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"declined":true}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
private final class ProductionDiagnostics {
    let sessions = DebugDrawerSessions(maximumDuration: 15 * 60)
    let receiver: DebugDrawerReceiver
    let capture: DebugDrawerDiagnosticsCapture

    init(container: URL) throws {
        receiver = DebugDrawerReceiver(directory: container.appending(path: "DebugDrawer"), sessions: sessions)
        capture = DebugDrawerDiagnosticsCapture(sessions: sessions)
        receiver.enable(.diagnosticsCapture(capture))
        try receiver.start()
    }

    func checkout(_ request: URLRequest, session: URLSession) async throws {
        // The app's logger's backend:
        capture.log(level: .error, message: "Payment declined", metadata: ["order": "1042"], subsystem: "com.example.shop")

        // The app's networking code, once it has the outcome:
        let started = Date()
        let (data, response) = try await session.data(for: request)
        capture.record(request, response: response, body: data, started: started)
    }
}

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct DiagnosticsCaptureREADMETests {
    @Test("README: once a sidecar starts the capture in its session, the app's line and request are captured")
    func readmeDiagnosticsCapture() async throws {
        let container = FileManager.default.temporaryDirectory.appending(path: "READMEDiagnostics-\(UUID().uuidString)")
        let app = try ProductionDiagnostics(container: container)
        defer { app.receiver.stop() }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubServer.self]
        let session = URLSession(configuration: configuration)
        let request = URLRequest(url: try #require(URL(string: "https://api.example.com/checkout")))
        let (published, publish) = AsyncStream<DebugDrawerDiagnosticsCapture.Snapshot>.makeStream()
        let subscription = app.capture.$snapshot.sink { publish.yield($0) }
        defer { subscription.cancel() }
        var changes = published.makeAsyncIterator()
        app.sessions.perform(.open(duration: 60))
        app.capture.perform(.start)

        try await app.checkout(request, session: session)

        var actual = app.capture.snapshot
        while actual.requests.isEmpty || actual.lines.isEmpty, let next = await changes.next() {
            actual = next
        }
        #expect(actual.lines.map(\.message) == ["Payment declined"])
        #expect(actual.lines.first?.metadata == ["order": "1042"])
        #expect(actual.requests.first?.statusCode == 402)
        #expect(actual.requests.first?.responseBody == .json(#"{"declined":true}"#))
    }
}
