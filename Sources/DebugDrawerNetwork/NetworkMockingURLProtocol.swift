import Foundation

// How a release build answers requests without intercepting anything: the host lists this class
// in the `protocolClasses` of the `URLSessionConfiguration`s it chooses, which is URL loading's own
// public, per-session extension point. Nothing is registered with `URLProtocol.registerClass`, no
// method is replaced, and a session the host didn't configure never reaches this class (the
// charter's N1). The protocol claims only a request a sidecar's rule answers, to a host the app
// allows, while a session is open; every other request it declines in `canInit`, so URL loading
// sends it through the system's protocols as if this class weren't listed. It never sends a
// request itself and never reads a server's response or the request's body.
//
// Rejected: registering the class globally or replacing `URLSessionConfiguration.protocolClasses`,
// as the debug plugin does (interception in the shipped build, reaching every session, the app's
// SDKs' included); a `URLSession` wrapper or delegate the host routes requests through (a second
// API for every call site, which misses the task types and delegates the wrapper doesn't model);
// and forwarding unmatched requests through a session of the library's own to delay or pace them
// (the library would send the app's traffic and read its responses, outside the app's own session
// delegate, its pinning included). So conditioning applies to the answers the rules give.

/// The URL protocol that answers a request from a sidecar's ``NetworkMockRule``s, during its
/// session, when the host lists it in a session's configuration.
///
/// List it first, in each session whose requests a sidecar may mock:
///
/// ```swift
/// let configuration = URLSessionConfiguration.default
/// configuration.protocolClasses = [NetworkMockingURLProtocol.self] + (configuration.protocolClasses ?? [])
/// ```
///
/// It answers only a request that a rule of an open session matches, over HTTP or HTTPS, to a host
/// in ``NetworkMocking/allowedHosts``, before the session's expiry; it declines every other
/// request, which then loads as if it weren't listed. An answer never enters the session's cache.
/// A session not configured with it is never touched.
public final class NetworkMockingURLProtocol: URLProtocol, @unchecked Sendable {
    // `@unchecked Sendable`: its state is kept on the thread URL loading started it on
    // (`NetworkClientThread`), where `startLoading()` and `stopLoading()` are called; what a
    // conditioned delivery reports is handed to that thread before it touches the state or the
    // client.

    /// Where `startLoading()` was called; the client is told there.
    private var clientThread: NetworkClientThread?
    /// Set by `stopLoading()`, after which the client hears nothing more.
    private var isStopped = false
    /// Times the answer when a conditioning profile applies; `nil` answers at once.
    private var delivery: NetworkConditionedDelivery?

    /// Whether a rule in effect answers `request`: a session is open, the request is HTTP or
    /// HTTPS to an allowed host, and a rule that is on matches it.
    ///
    /// - Parameter request: The request URL loading asks about.
    /// - Returns: `true` when this protocol answers it; `false` leaves it to the system.
    override public static func canInit(with request: URLRequest) -> Bool {
        guard let url = request.url else { return false }
        return NetworkMockingRoute.shared.claims(method: request.httpMethod ?? "GET", url: url)
    }

    /// Whether a rule in effect answers `task`'s request; never for a WebSocket task, whose
    /// handshake an answer here would never upgrade.
    ///
    /// - Parameter task: The task URL loading asks about.
    /// - Returns: `true` when this protocol answers it.
    override public static func canInit(with task: URLSessionTask) -> Bool {
        guard !(task is URLSessionWebSocketTask) else { return false }
        return super.canInit(with: task)
    }

    /// `request` as it is: answering it changes nothing about it.
    ///
    /// - Parameter request: The request.
    /// - Returns: The same request.
    override public static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    /// Answers the request from the first rule that matches it: the response, the body and the
    /// finish, after the latency and at the bandwidth of a profile that conditions it, or the
    /// failure the profile decides. No request is sent.
    override public func startLoading() {
        clientThread = .current
        guard let url = request.url, let match = NetworkMockingRoute.shared.resolve(method: request.httpMethod ?? "GET", url: url) else {
            // The rules changed between URL loading asking and starting: the session ended, or the
            // sidecar replaced them. The request is this protocol's now and can't go on to the
            // network, so it fails as a dropped connection does, which an app already retries.
            client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
            return
        }
        let answer = match.answer
        guard let plan = match.plan else {
            respond(with: answer, to: url)
            return
        }
        let delivery = NetworkConditionedDelivery(plan: plan) { [weak self] event in
            self?.clientThread?.perform { [weak self] in
                self?.forward(event)
            }
        }
        self.delivery = delivery
        delivery.start(url: url) { [weak delivery] in
            // `HTTPURLResponse`'s initializer returns nil only for a URL it can't use, and the
            // request's own URL loaded this far.
            guard let response = HTTPURLResponse(url: url, statusCode: answer.status, httpVersion: "HTTP/1.1", headerFields: answer.headers) else {
                delivery?.fail(URLError(.badServerResponse) as NSError)
                return
            }
            delivery?.deliver(response, body: answer.body)
        }
    }

    /// Stops the answer: nothing more reaches the client, and a scheduled step is cancelled.
    override public func stopLoading() {
        isStopped = true
        delivery?.cancel()
    }

    /// Answers at once: the response, the body and the finish.
    private func respond(with answer: NetworkMockAnswer, to url: URL) {
        guard let response = HTTPURLResponse(url: url, statusCode: answer.status, httpVersion: "HTTP/1.1", headerFields: answer.headers) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        // A mock's answer never enters the app's cache, so the next request asks the rules again.
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !answer.body.isEmpty {
            client?.urlProtocol(self, didLoad: answer.body)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    /// Tells the client of a conditioned answer's event, unless loading stopped.
    private func forward(_ event: NetworkConditionedDelivery.Event) {
        guard !isStopped else { return }
        switch event {
        case let .response(response):
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        case let .data(data):
            client?.urlProtocol(self, didLoad: data)
        case .finished:
            client?.urlProtocolDidFinishLoading(self)
        case let .failed(error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
}
