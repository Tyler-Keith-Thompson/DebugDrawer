import Foundation

// The vocabulary of a capture: its bounds, a log line, a request, a body, an export record and
// the snapshot a sidecar reads. Each entry holds only what redaction left, so the snapshot (and
// the store's file of it) never holds what was masked. Sizes count the UTF-8 bytes of the text
// kept, which is what the store writes; they bound the capture, they aren't an exact file size.

extension DebugDrawerDiagnosticsCapture {
    /// How much one session's capture keeps: when a bound is reached, the oldest entries go first.
    public struct Limits: Codable, Equatable, Sendable {
        /// The bounds the capture keeps unless the host passes others: 1,000 log lines, 200
        /// requests, bodies of up to 64 KiB, 2 MiB in all.
        public static let standard = Limits(lines: 1000, requests: 200, bodyBytes: 64 << 10, totalBytes: 2 << 20)

        /// The most log lines kept, the newest.
        public let lines: Int
        /// The most requests kept, the newest.
        public let requests: Int
        /// The largest request or response body kept, in bytes; a larger one is left out, its
        /// size kept.
        public let bodyBytes: Int
        /// The most bytes of text the capture keeps, lines and requests together; the oldest entries
        /// go until it fits.
        public let totalBytes: Int

        /// Bounds for one session's capture.
        ///
        /// - Parameters:
        ///   - lines: The most log lines kept.
        ///   - requests: The most requests kept.
        ///   - bodyBytes: The largest body kept, in bytes.
        ///   - totalBytes: The most bytes kept in all.
        /// - Precondition: `lines`, `requests` and `totalBytes` are at least 1, and `bodyBytes` at
        ///   least 0.
        public init(lines: Int, requests: Int, bodyBytes: Int, totalBytes: Int) {
            precondition(lines > 0 && requests > 0 && totalBytes > 0 && bodyBytes >= 0, "A diagnostics capture keeps at least one of each")
            self.lines = lines
            self.requests = requests
            self.bodyBytes = bodyBytes
            self.totalBytes = totalBytes
        }
    }

    /// How severe a log line is.
    public enum Level: String, Codable, Sendable, CaseIterable {
        /// Detail for debugging.
        case debug
        /// An ordinary event.
        case info
        /// An event worth noticing.
        case notice
        /// A failure.
        case error
        /// A failure in the app's own logic.
        case fault
    }

    /// A log line the app handed the capture, as redaction left it.
    public struct LogLine: Codable, Equatable, Identifiable, Sendable {
        /// Its place in the order the session's lines and requests were captured, from 1.
        public let id: Int
        /// When it was logged.
        public let timestamp: Date
        /// How severe it is.
        public let level: Level
        /// What was logged, with the text value patterns matched masked.
        public let message: String
        /// Its key/value fields, each sensitive key's value masked.
        public let metadata: [String: String]
        /// What logged it, as the app named it; empty for none.
        public let subsystem: String
        /// Its category within the subsystem; empty for none.
        public let category: String

        /// A log line.
        ///
        /// - Parameters:
        ///   - id: Its place in the session's order.
        ///   - timestamp: When it was logged.
        ///   - level: How severe it is.
        ///   - message: What was logged.
        ///   - metadata: Its key/value fields.
        ///   - subsystem: What logged it.
        ///   - category: Its category.
        public init(id: Int, timestamp: Date, level: Level, message: String, metadata: [String: String], subsystem: String, category: String) {
            self.id = id
            self.timestamp = timestamp
            self.level = level
            self.message = message
            self.metadata = metadata
            self.subsystem = subsystem
            self.category = category
        }
    }

    /// A request body or response body, as the capture kept it.
    public enum Body: Codable, Equatable, Sendable {
        /// A JSON body, redacted and re-encoded with sorted keys.
        case json(String)
        /// A body left out, and why, with its size in bytes.
        case omitted(Omission, byteCount: Int)
    }

    /// Why a body was left out.
    public enum Omission: String, Codable, Sendable {
        /// It isn't JSON, so redaction can't read it.
        case notJSON
        /// It is larger than ``Limits/bodyBytes``.
        case tooLarge
    }

    /// A request the app sent and what came back, as redaction left them.
    public struct Request: Codable, Equatable, Identifiable, Sendable {
        /// Its place in the order the session's lines and requests were captured, from 1.
        public let id: Int
        /// When the app sent it.
        public let started: Date
        /// When the app recorded its outcome.
        public let finished: Date
        /// Its HTTP method.
        public let method: String
        /// Its URL, its user, password and sensitive query items masked.
        public let url: String
        /// The headers the app set on it.
        public let requestHeaders: [String: String]
        /// Its body, if it had one.
        public let requestBody: Body?
        /// The response's HTTP status, or `nil` without an HTTP response.
        public let statusCode: Int?
        /// The response's headers.
        public let responseHeaders: [String: String]
        /// The response's body, if it had one.
        public let responseBody: Body?
        /// The failure, as its error domain and code (`NSURLErrorDomain -1001`), never its message;
        /// `nil` when it didn't fail.
        public let failure: String?

        /// A request.
        ///
        /// - Parameters:
        ///   - id: Its place in the session's order.
        ///   - started: When it was sent.
        ///   - finished: When its outcome was recorded.
        ///   - method: Its HTTP method.
        ///   - url: Its URL.
        ///   - requestHeaders: Its headers.
        ///   - requestBody: Its body.
        ///   - statusCode: The response's status.
        ///   - responseHeaders: The response's headers.
        ///   - responseBody: The response's body.
        ///   - failure: The failure's domain and code.
        public init(
            id: Int, started: Date, finished: Date, method: String, url: String,
            requestHeaders: [String: String], requestBody: Body?,
            statusCode: Int?, responseHeaders: [String: String], responseBody: Body?, failure: String?
        ) {
            self.id = id
            self.started = started
            self.finished = finished
            self.method = method
            self.url = url
            self.requestHeaders = requestHeaders
            self.requestBody = requestBody
            self.statusCode = statusCode
            self.responseHeaders = responseHeaders
            self.responseBody = responseBody
            self.failure = failure
        }
    }

    /// A copy of the capture a sidecar took into its report, as the app recorded it.
    public struct Export: Codable, Equatable, Sendable {
        /// When the sidecar exported it.
        public let date: Date
        /// How many log lines the capture held then.
        public let lines: Int
        /// How many requests it held then.
        public let requests: Int

        /// An export record.
        ///
        /// - Parameters:
        ///   - date: When it was exported.
        ///   - lines: How many log lines the capture held.
        ///   - requests: How many requests it held.
        public init(date: Date, lines: Int, requests: Int) {
            self.date = date
            self.lines = lines
            self.requests = requests
        }
    }

    /// What a sidecar sees.
    public struct Snapshot: Codable, Equatable, Sendable {
        /// The session the capture runs in, or `nil` while it isn't capturing.
        public var sessionID: UUID?
        /// The log lines kept, oldest first.
        public var lines: [LogLine]
        /// The requests kept, oldest first.
        public var requests: [Request]
        /// How many lines and requests the bounds dropped so far.
        public var dropped: Int
        /// The bytes of text the capture keeps now.
        public var byteCount: Int
        /// The bounds it keeps to.
        public var limits: Limits
        /// The copies a sidecar took this session, oldest first.
        public var exports: [Export]

        /// Whether the capture is running: a sidecar started it in the session now open.
        public var isCapturing: Bool {
            sessionID != nil
        }

        /// A snapshot.
        ///
        /// - Parameters:
        ///   - sessionID: The session the capture runs in, or `nil`.
        ///   - lines: The lines kept.
        ///   - requests: The requests kept.
        ///   - dropped: How many entries the bounds dropped.
        ///   - byteCount: The bytes kept.
        ///   - limits: The bounds.
        ///   - exports: The session's exports.
        public init(
            sessionID: UUID?, lines: [LogLine], requests: [Request], dropped: Int, byteCount: Int, limits: Limits, exports: [Export]
        ) {
            self.sessionID = sessionID
            self.lines = lines
            self.requests = requests
            self.dropped = dropped
            self.byteCount = byteCount
            self.limits = limits
            self.exports = exports
        }

        /// The log lines as text for a bug report, one per line: `<ISO 8601 time> [<level>]
        /// <subsystem>/<category>: <message> key=value…`, oldest first. It holds only what
        /// redaction left.
        public var consoleLog: String {
            lines.map(\.reportLine).joined(separator: "\n")
        }

        /// The requests as JSON for a bug report, oldest first, with sorted keys and ISO 8601 dates.
        /// It holds only what redaction left.
        public var networkJSON: Data {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .iso8601
            // Every member is a string, number, date, optional or collection of them, which JSON
            // always encodes.
            return (try? encoder.encode(requests)) ?? Data("[]".utf8)
        }
    }
}

extension DebugDrawerDiagnosticsCapture.LogLine {
    /// The line as `console.log` writes it.
    fileprivate var reportLine: String {
        let source = [subsystem, category].filter { !$0.isEmpty }.joined(separator: "/")
        let fields = metadata.keys.sorted().map { "\($0)=\(metadata[$0] ?? "")" }
        return ([timestamp.ISO8601Format(), "[\(level.rawValue)]", source.isEmpty ? nil : "\(source):", message] + fields)
            .compactMap(\.self)
            .joined(separator: " ")
    }

    /// The bytes of text the line keeps.
    var byteCount: Int {
        message.utf8.count + subsystem.utf8.count + category.utf8.count + metadata.byteCount
    }
}

extension DebugDrawerDiagnosticsCapture.Request {
    /// The bytes of text the request keeps.
    var byteCount: Int {
        method.utf8.count + url.utf8.count + requestHeaders.byteCount + responseHeaders.byteCount
            + (requestBody?.byteCount ?? 0) + (responseBody?.byteCount ?? 0) + (failure?.utf8.count ?? 0)
    }
}

extension DebugDrawerDiagnosticsCapture.Body {
    /// The bytes of text the body keeps: none when it was left out.
    fileprivate var byteCount: Int {
        switch self {
        case let .json(text): text.utf8.count
        case .omitted: 0
        }
    }
}

extension [String: String] {
    /// The bytes of the keys and values.
    fileprivate var byteCount: Int {
        reduce(0) { $0 + $1.key.utf8.count + $1.value.utf8.count }
    }
}
