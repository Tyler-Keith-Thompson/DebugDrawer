import Foundation
import os

// The part of a capture the app's logger and networking code reach, from any thread. It holds the
// session's capture itself, behind a lock: what arrives is redacted on the calling thread before
// the lock is taken, so nothing unredacted is ever kept, and the bounds are applied as each entry is
// added, so the capture never holds more than they allow, however long the main actor is busy. It
// wakes the model on the main actor through a stream that keeps one wake-up, so a burst is one
// snapshot. An entry arriving at or after the session's expiry is dropped even if the expiry timer
// hasn't fired yet, as it may not have in an app coming back from suspension. A lock rather than an
// actor: a log call returns at once, and an asynchronous hop per line could reorder lines logged
// back to back. `OSAllocatedUnfairLock` rather than `Mutex`, which needs iOS 18; switch once iOS 18
// is the minimum.

/// One session's capture, as the app hands it lines and requests.
final class DiagnosticsCaptureInbox: Sendable {
    /// What the capture holds.
    struct State {
        /// The session it captures for, or `nil` while it captures nothing.
        var session: DebugDrawerSession?
        var lines: [DebugDrawerDiagnosticsCapture.LogLine] = []
        var requests: [DebugDrawerDiagnosticsCapture.Request] = []
        var dropped = 0
        var byteCount = 0
        /// The identity of the session's next entry.
        var nextID = 1
    }

    /// The rules each entry is redacted by before it is kept.
    let redaction: DebugDrawerDiagnosticsRedaction
    /// The bounds the capture keeps to.
    let limits: DebugDrawerDiagnosticsCapture.Limits
    /// The wake-ups: one waits after each entry that arrived while none was waiting.
    let wakeUps: AsyncStream<Void>

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let now: @Sendable () -> Date
    private let wake: AsyncStream<Void>.Continuation

    /// An inbox that takes nothing until ``open(_:)``.
    init(redaction: DebugDrawerDiagnosticsRedaction, limits: DebugDrawerDiagnosticsCapture.Limits, now: @escaping @Sendable () -> Date) {
        self.redaction = redaction
        self.limits = limits
        self.now = now
        (wakeUps, wake) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
    }

    /// Whether it is capturing for a session, so what the app hands it now would be kept.
    var isCapturing: Bool {
        state.withLock { $0.session != nil }
    }

    /// Captures from now until `session` expires or ``close()``, starting empty.
    func open(_ session: DebugDrawerSession) {
        state.withLock { $0 = State(session: session) }
    }

    /// Captures nothing more and drops everything captured.
    func close() {
        state.withLock { $0 = State() }
    }

    /// Closes the inbox and ends ``wakeUps``.
    func finish() {
        close()
        wake.finish()
    }

    /// What the capture holds now.
    func current() -> State {
        state.withLock { $0 }
    }

    /// Keeps a log line, redacted, if a session is capturing and hasn't expired.
    func receive(level: DebugDrawerDiagnosticsCapture.Level, message: String, metadata: [String: String], subsystem: String, category: String) {
        let timestamp = now()
        let message = redaction.redacting(text: message)
        let metadata = redaction.redacting(fields: metadata)
        keep(at: timestamp) { id in
            .line(DebugDrawerDiagnosticsCapture.LogLine(
                id: id, timestamp: timestamp, level: level, message: message, metadata: metadata, subsystem: subsystem, category: category
            ))
        }
    }

    /// Keeps a request and its outcome, redacted, if a session is capturing and hasn't expired.
    func receive(request: URLRequest, response: URLResponse?, body: Data?, error: (any Error)?, started: Date) {
        let finished = now()
        let http = response as? HTTPURLResponse
        let method = request.httpMethod ?? "GET"
        let url = request.url.map(redaction.redacting(url:)) ?? ""
        let requestHeaders = redaction.redacting(headers: request.allHTTPHeaderFields ?? [:])
        let requestBody = kept(request.httpBody)
        let responseHeaders = redaction.redacting(headers: http?.stringHeaderFields ?? [:])
        let responseBody = kept(body)
        let failure = error.map { error in
            let error = error as NSError
            return "\(error.domain) \(error.code)"
        }
        keep(at: finished) { id in
            .request(DebugDrawerDiagnosticsCapture.Request(
                id: id, started: started, finished: finished, method: method, url: url,
                requestHeaders: requestHeaders, requestBody: requestBody,
                statusCode: http?.statusCode, responseHeaders: responseHeaders, responseBody: responseBody, failure: failure
            ))
        }
    }

    private enum Entry: Sendable {
        case line(DebugDrawerDiagnosticsCapture.LogLine)
        case request(DebugDrawerDiagnosticsCapture.Request)
    }

    /// Adds the entry `make` builds with the next identity, if a session is capturing and
    /// `timestamp` is before its expiry, then applies the bounds and wakes the model.
    private func keep(at timestamp: Date, _ make: @Sendable (Int) -> Entry) {
        let limits = limits
        let kept = state.withLock { state -> Bool in
            guard let session = state.session, timestamp < session.expires else { return false }
            switch make(state.nextID) {
            case let .line(line):
                state.lines.append(line)
                state.byteCount += line.byteCount
            case let .request(request):
                state.requests.append(request)
                state.byteCount += request.byteCount
            }
            state.nextID += 1
            state.applyBounds(limits)
            return true
        }
        if kept {
            wake.yield()
        }
    }

    /// `data` as the capture keeps a body: JSON redacted, or left out with its size.
    private func kept(_ data: Data?) -> DebugDrawerDiagnosticsCapture.Body? {
        guard let data, !data.isEmpty else { return nil }
        guard data.count <= limits.bodyBytes else { return .omitted(.tooLarge, byteCount: data.count) }
        guard let redacted = redaction.redacting(json: data), let text = String(data: redacted, encoding: .utf8) else {
            return .omitted(.notJSON, byteCount: data.count)
        }
        return .json(text)
    }
}

extension DiagnosticsCaptureInbox.State {
    /// Drops the oldest lines and requests until each count and the bytes in all fit `limits`.
    ///
    /// - Complexity: O(*n*) per entry dropped, in the entries kept, which the bounds keep small.
    fileprivate mutating func applyBounds(_ limits: DebugDrawerDiagnosticsCapture.Limits) {
        while lines.count > limits.lines {
            dropOldestLine()
        }
        while requests.count > limits.requests {
            dropOldestRequest()
        }
        while byteCount > limits.totalBytes, !(lines.isEmpty && requests.isEmpty) {
            // Identities rise across lines and requests, so the smaller is the older.
            if lines.first?.id ?? .max < requests.first?.id ?? .max {
                dropOldestLine()
            } else {
                dropOldestRequest()
            }
        }
    }

    private mutating func dropOldestLine() {
        byteCount -= lines.removeFirst().byteCount
        dropped += 1
    }

    private mutating func dropOldestRequest() {
        byteCount -= requests.removeFirst().byteCount
        dropped += 1
    }
}

extension HTTPURLResponse {
    /// The headers, each name and value as a string.
    fileprivate var stringHeaderFields: [String: String] {
        allHeaderFields.reduce(into: [:]) { result, field in
            if let name = field.key as? String {
                result[name] = field.value as? String ?? "\(field.value)"
            }
        }
    }
}
