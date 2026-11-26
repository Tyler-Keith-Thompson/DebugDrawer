import Combine
@testable import DebugDrawerReceiver
import Foundation
import os
import Testing

/// A wall clock the test moves by hand.
private final class MovableClock: SessionClock, Sendable {
    private let time: OSAllocatedUnfairLock<Date>

    init(_ start: Date) {
        time = OSAllocatedUnfairLock(initialState: start)
    }

    var now: Date {
        time.withLock { $0 }
    }

    func set(_ date: Date) {
        time.withLock { $0 = date }
    }
}

/// A session timer that never fires: these sessions end only when the test ends them.
@MainActor
private final class IdleTimer: SessionTimer {
    func schedule(at date: Date, _ fire: @escaping @MainActor () -> Void) {}
    func cancel() {}
}

// The capture's model driven directly, as the receiver would within a session: its bounds (each
// count, the bytes in all, the size of a body), what it keeps of a body, and what start, stop and
// export do. What the app hands it arrives on the main actor through the inbox's wake-up, so each
// test reads the snapshots the model publishes until the one it waits for.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct DiagnosticsCaptureTests {
    private static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test("Past the line limit the oldest lines go, and each one dropped is counted")
    func lineLimitKeepsNewest() async throws {
        let clock = MovableClock(Self.now)
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 10, clock: clock, timer: IdleTimer())
        let limits = try DebugDrawerDiagnosticsCapture.Limits(lines: 2, requests: 2, bodyBytes: 1024, totalBytes: 1 << 20)
        let sut = DebugDrawerDiagnosticsCapture(sessions: sessions, redaction: .none, limits: limits) { clock.now }
        let (published, publish) = AsyncStream<DebugDrawerDiagnosticsCapture.Snapshot>.makeStream()
        let subscription = sut.$snapshot.sink { publish.yield($0) }
        defer { subscription.cancel() }
        var changes = published.makeAsyncIterator()
        sessions.perform(.open(duration: 60))
        sut.perform(.start)

        sut.log(level: .info, message: "one")
        sut.log(level: .info, message: "two")
        sut.log(level: .info, message: "three")

        var actual = sut.snapshot
        while actual.lines.last?.message != "three", let next = await changes.next() {
            actual = next
        }
        #expect(actual.lines.map(\.message) == ["two", "three"])
        #expect(actual.lines.map(\.id) == [2, 3])
        #expect(actual.dropped == 1)
        #expect(actual.byteCount == 8)
    }

    @Test("Past the request limit the oldest requests go")
    func requestLimitKeepsNewest() async throws {
        let clock = MovableClock(Self.now)
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 10, clock: clock, timer: IdleTimer())
        let limits = try DebugDrawerDiagnosticsCapture.Limits(lines: 10, requests: 1, bodyBytes: 1024, totalBytes: 1 << 20)
        let sut = DebugDrawerDiagnosticsCapture(sessions: sessions, redaction: .none, limits: limits) { clock.now }
        let (published, publish) = AsyncStream<DebugDrawerDiagnosticsCapture.Snapshot>.makeStream()
        let subscription = sut.$snapshot.sink { publish.yield($0) }
        defer { subscription.cancel() }
        var changes = published.makeAsyncIterator()
        sessions.perform(.open(duration: 60))
        sut.perform(.start)
        let first = URLRequest(url: try #require(URL(string: "https://api.example.com/a")))
        let second = URLRequest(url: try #require(URL(string: "https://api.example.com/b")))

        sut.record(first, started: Self.now)
        sut.record(second, started: Self.now)

        var actual = sut.snapshot
        while actual.requests.last?.url != "https://api.example.com/b", let next = await changes.next() {
            actual = next
        }
        #expect(actual.requests.map(\.url) == ["https://api.example.com/b"])
        #expect(actual.dropped == 1)
    }

    @Test("Past the byte limit the oldest entries go, lines and requests alike, until the rest fits")
    func byteLimitDropsOldest() async throws {
        let clock = MovableClock(Self.now)
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 10, clock: clock, timer: IdleTimer())
        // Each line below keeps 10 bytes, the request 3 + 25 = 28 (method and URL).
        let limits = try DebugDrawerDiagnosticsCapture.Limits(lines: 10, requests: 10, bodyBytes: 1024, totalBytes: 40)
        let sut = DebugDrawerDiagnosticsCapture(sessions: sessions, redaction: .none, limits: limits) { clock.now }
        let (published, publish) = AsyncStream<DebugDrawerDiagnosticsCapture.Snapshot>.makeStream()
        let subscription = sut.$snapshot.sink { publish.yield($0) }
        defer { subscription.cancel() }
        var changes = published.makeAsyncIterator()
        sessions.perform(.open(duration: 60))
        sut.perform(.start)
        let request = URLRequest(url: try #require(URL(string: "https://example.com/order")))

        sut.log(level: .info, message: "0123456789")
        sut.log(level: .info, message: "abcdefghij")
        sut.record(request, started: Self.now)
        sut.log(level: .info, message: "klmnopqrst")

        var actual = sut.snapshot
        while actual.lines.last?.message != "klmnopqrst", let next = await changes.next() {
            actual = next
        }
        #expect(actual.lines.map(\.message) == ["klmnopqrst"])
        #expect(actual.requests.map(\.url) == ["https://example.com/order"])
        #expect(actual.byteCount == 38)
        #expect(actual.dropped == 2)
    }

    @Test("A body over the body limit, or one within it that isn't JSON, is left out with its size; a JSON body within it is kept")
    func bodiesKeptOnlyWhenJSONWithinLimit() async throws {
        let clock = MovableClock(Self.now)
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 10, clock: clock, timer: IdleTimer())
        let limits = try DebugDrawerDiagnosticsCapture.Limits(lines: 10, requests: 10, bodyBytes: 32, totalBytes: 1 << 20)
        let sut = DebugDrawerDiagnosticsCapture(sessions: sessions, redaction: .none, limits: limits) { clock.now }
        let (published, publish) = AsyncStream<DebugDrawerDiagnosticsCapture.Snapshot>.makeStream()
        let subscription = sut.$snapshot.sink { publish.yield($0) }
        defer { subscription.cancel() }
        var changes = published.makeAsyncIterator()
        sessions.perform(.open(duration: 60))
        sut.perform(.start)
        var request = URLRequest(url: try #require(URL(string: "https://api.example.com/upload")))
        request.httpBody = Data("name=jane&card=4111".utf8)
        let large = Data(#"{"note":"far more than thirty-two bytes of JSON"}"#.utf8)
        let small = Data(#"{"ok":true}"#.utf8)
        let ok = URLRequest(url: try #require(URL(string: "https://api.example.com/ok")))
        let empty = URLRequest(url: try #require(URL(string: "https://api.example.com/empty")))
        let expectedBodies: [DebugDrawerDiagnosticsCapture.Body?] = [.omitted(.notJSON, byteCount: 19), .omitted(.tooLarge, byteCount: large.count)]

        sut.record(request, body: large, started: Self.now)
        sut.record(ok, body: small, started: Self.now)
        sut.record(empty, body: Data(), started: Self.now)

        var actual = sut.snapshot
        while actual.requests.count < 3, let next = await changes.next() {
            actual = next
        }
        #expect([actual.requests[0].requestBody, actual.requests[0].responseBody] == expectedBodies)
        #expect(actual.requests[1].responseBody == .json(#"{"ok":true}"#))
        #expect(actual.requests[2].responseBody == nil)
    }

    @Test("A failure keeps its error domain and code, never its message")
    func failureKeepsDomainAndCode() async throws {
        let clock = MovableClock(Self.now)
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 10, clock: clock, timer: IdleTimer())
        let sut = DebugDrawerDiagnosticsCapture(sessions: sessions, redaction: .standard, limits: .standard) { clock.now }
        let (published, publish) = AsyncStream<DebugDrawerDiagnosticsCapture.Snapshot>.makeStream()
        let subscription = sut.$snapshot.sink { publish.yield($0) }
        defer { subscription.cancel() }
        var changes = published.makeAsyncIterator()
        sessions.perform(.open(duration: 60))
        sut.perform(.start)
        let error = URLError(.timedOut, userInfo: [NSLocalizedDescriptionKey: "Timed out for jane@example.com"])
        let request = URLRequest(url: try #require(URL(string: "https://api.example.com/slow")))

        sut.record(request, error: error, started: Self.now)

        var actual = sut.snapshot
        while actual.requests.isEmpty, let next = await changes.next() {
            actual = next
        }
        #expect(actual.requests.first?.failure == "NSURLErrorDomain -1001")
        #expect(actual.requests.first?.statusCode == nil)
    }

    @Test("Start outside a session does nothing; started, stop empties the capture and later lines are dropped")
    func startAndStop() async {
        let clock = MovableClock(Self.now)
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 10, clock: clock, timer: IdleTimer())
        let sut = DebugDrawerDiagnosticsCapture(sessions: sessions, redaction: .none, limits: .standard) { clock.now }
        let (published, publish) = AsyncStream<DebugDrawerDiagnosticsCapture.Snapshot>.makeStream()
        let subscription = sut.$snapshot.sink { publish.yield($0) }
        defer { subscription.cancel() }
        var changes = published.makeAsyncIterator()

        sut.perform(.start)
        let outside = sut.snapshot.isCapturing
        sessions.perform(.open(duration: 60))
        sut.perform(.start)
        sut.log(level: .info, message: "during")
        var during = sut.snapshot
        while during.lines.isEmpty, let next = await changes.next() {
            during = next
        }
        sut.perform(.stop)
        sut.log(level: .info, message: "after")

        #expect(!outside)
        #expect(during.lines.map(\.message) == ["during"])
        #expect(!sut.snapshot.isCapturing)
        #expect(sut.snapshot.lines.isEmpty)
    }

    @Test("Each capture is a session's own: a new session starts empty, with its own numbering")
    func newSessionStartsEmpty() async {
        let clock = MovableClock(Self.now)
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 10, clock: clock, timer: IdleTimer())
        let sut = DebugDrawerDiagnosticsCapture(sessions: sessions, redaction: .none, limits: .standard) { clock.now }
        let (published, publish) = AsyncStream<DebugDrawerDiagnosticsCapture.Snapshot>.makeStream()
        let subscription = sut.$snapshot.sink { publish.yield($0) }
        defer { subscription.cancel() }
        var changes = published.makeAsyncIterator()
        sessions.perform(.open(duration: 60))
        sut.perform(.start)
        sut.log(level: .info, message: "first session")
        var first = sut.snapshot
        while first.lines.isEmpty, let next = await changes.next() {
            first = next
        }

        sessions.end()
        let ended = sut.snapshot
        sessions.perform(.open(duration: 60))
        let beforeStart = sut.snapshot
        sut.perform(.start)
        let secondSession = sessions.snapshot.session?.id
        sut.log(level: .info, message: "second session")
        var second = sut.snapshot
        while second.sessionID != secondSession || second.lines.isEmpty, let next = await changes.next() {
            second = next
        }

        #expect(first.lines.map(\.message) == ["first session"])
        #expect(!ended.isCapturing && ended.lines.isEmpty)
        #expect(!beforeStart.isCapturing)
        #expect(second.sessionID == secondSession)
        #expect(second.lines.map(\.message) == ["second session"])
        #expect(second.lines.map(\.id) == [1])
    }

    @Test("The report's console log has a line per log line: time, level, source, message, sorted fields; its network JSON decodes to the requests")
    func reportForms() throws {
        let request = DebugDrawerDiagnosticsCapture.Request(
            id: 3, started: Self.now, finished: Self.now.addingTimeInterval(1), method: "GET", url: "https://api.example.com/a",
            requestHeaders: [:], requestBody: nil, statusCode: 200, responseHeaders: ["Content-Type": "application/json"],
            responseBody: .json("{}"), failure: nil
        )
        let sut = DebugDrawerDiagnosticsCapture.Snapshot(
            sessionID: UUID(),
            lines: [
                DebugDrawerDiagnosticsCapture.LogLine(
                    id: 1, timestamp: Self.now, level: .error, message: "Declined", metadata: ["b": "2", "a": "1"], subsystem: "shop", category: "pay"
                ),
                DebugDrawerDiagnosticsCapture.LogLine(
                    id: 2, timestamp: Self.now, level: .debug, message: "Bare", metadata: [:], subsystem: "", category: ""
                )
            ],
            requests: [request], dropped: 0, byteCount: 0, limits: .standard, exports: []
        )
        let expectedConsole = "2026-05-09T06:13:20Z [error] shop/pay: Declined a=1 b=2\n2026-05-09T06:13:20Z [debug] Bare"
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let console = sut.consoleLog
        let network = try decoder.decode([DebugDrawerDiagnosticsCapture.Request].self, from: sut.networkJSON)

        #expect(console == expectedConsole)
        #expect(network == [request])
    }
}
