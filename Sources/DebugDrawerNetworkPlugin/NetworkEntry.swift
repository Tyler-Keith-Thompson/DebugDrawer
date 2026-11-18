import Foundation

/// A request the log holds: what the app sent, and once it completes, what came back.
public struct NetworkEntry: Identifiable, Sendable {
    public let id = UUID()
    public let timestamp: Date
    public let method: String
    public let url: String
    public let host: String
    public let path: String
    public let requestHeaders: [String: String]
    /// The request's body as the log keeps it: all of it, or its first bytes when it was larger
    /// than `installNetwork(bodyLimit:)` allows (`isRequestBodyTruncated`). The server gets the
    /// whole body either way.
    public let requestBody: Data?
    /// How many bytes the request's body had, all told: more than `requestBody` holds when the
    /// log kept only its first bytes. `nil` when there is no body.
    public let requestBodySize: Int?

    /// Whether the log kept only the first bytes of the request's body, which had
    /// `requestBodySize` bytes in all.
    public var isRequestBodyTruncated: Bool {
        requestBody.map { (requestBodySize ?? 0) > $0.count } ?? false
    }

    public var statusCode: Int?
    public var responseHeaders: [String: String]?
    /// The response's body as the log keeps it: all of it, or its first bytes when it was larger
    /// than `installNetwork(bodyLimit:)` allows (`isResponseBodyTruncated`). The app gets the
    /// whole body either way.
    public var responseBody: Data? {
        get { response?.data }
        set { response = newValue.map { NetworkResponseBody($0) } }
    }

    /// How many bytes the response's body had, all told: more than `responseBody` holds when
    /// the log kept only its first bytes. `nil` when there is no body.
    public var responseBodySize: Int? {
        response?.size
    }

    /// Whether the log kept only the first bytes of the response's body, which had
    /// `responseBodySize` bytes in all.
    public var isResponseBodyTruncated: Bool {
        response.map { $0.size > $0.data.count } ?? false
    }

    /// The response's body with the text the log's filter searches, worked out once, when the
    /// body is set, rather than on every keystroke.
    var response: NetworkResponseBody?
    public var duration: TimeInterval?
    public var error: String?
    public var isComplete: Bool
    /// Timing of the request's last transaction, from `URLSessionTaskMetrics`.
    public var metrics: NetworkTimingMetrics?
    /// The name of the mock rule that answered the request, or `nil` when the network did.
    public var mockRuleName: String?
    /// What a conditioning profile did to the request, or `nil` when none applied.
    public var conditionEffect: NetworkConditionEffect?
    /// The id of the captured request this one resends, when the drawer's Resend or Edit and
    /// Resend sent it; `nil` for a request the app made.
    public var replayOf: UUID?
    /// The name of the GraphQL operation the request runs (`GetUser`), read once from its
    /// method, URL and body; `nil` when it isn't a GraphQL request or its operation is
    /// anonymous. See `graphQLOperationName(method:url:body:)` for what is read.
    public let graphQLOperationName: String?

    init(
        timestamp: Date,
        method: String,
        url: String,
        host: String,
        path: String,
        requestHeaders: [String: String],
        requestBody: Data?,
        requestBodySize: Int? = nil,
        statusCode: Int? = nil,
        responseHeaders: [String: String]? = nil,
        responseBody: Data? = nil,
        responseBodySize: Int? = nil,
        duration: TimeInterval? = nil,
        error: String? = nil,
        isComplete: Bool,
        metrics: NetworkTimingMetrics? = nil,
        mockRuleName: String? = nil,
        conditionEffect: NetworkConditionEffect? = nil,
        replayOf: UUID? = nil
    ) {
        self.timestamp = timestamp
        self.method = method
        self.url = url
        self.host = host
        self.path = path
        self.requestHeaders = requestHeaders
        self.requestBody = requestBody
        self.requestBodySize = requestBody.map { max(requestBodySize ?? $0.count, $0.count) }
        self.statusCode = statusCode
        self.responseHeaders = responseHeaders
        response = responseBody.map { NetworkResponseBody($0, size: responseBodySize) }
        self.duration = duration
        self.error = error
        self.isComplete = isComplete
        self.metrics = metrics
        self.mockRuleName = mockRuleName
        self.conditionEffect = conditionEffect
        self.replayOf = replayOf
        // Worked out here, once, as the request's fields never change: the log reads it on
        // every render and every keystroke in the filter. Release builds capture nothing, so they
        // carry no GraphQL parser.
        #if DEBUG
            graphQLOperationName = Self.graphQLOperationName(method: method, url: url, body: requestBody)
        #else
            graphQLOperationName = nil
        #endif
    }

    /// Whether the request failed: the server answered with a status of 400 or more, or the
    /// request never got an answer (a transport error).
    var isFailure: Bool {
        error != nil || (statusCode ?? 0) >= 400
    }

    /// The size of the response's body, all of it even when the log kept only its first bytes
    /// ("2 KB"), or "—" when there is none.
    public var responseSizeLabel: String {
        responseBodySize.map(Self.sizeLabel) ?? "—"
    }

    /// The size of the request's body, all of it even when the log kept only its first bytes
    /// ("2 KB"), or "—" when there is none.
    public var requestSizeLabel: String {
        requestBodySize.map(Self.sizeLabel) ?? "—"
    }

    /// `bytes` as the log shows a size: "512 B", "2 KB", "1.5 MB".
    static func sizeLabel(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return "\(bytes / 1024) KB" }
        return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }

    public var durationLabel: String {
        guard let duration else { return "..." }
        if duration < 1 { return String(format: "%.0fms", duration * 1000) }
        return String(format: "%.2fs", duration)
    }

    public var prettyResponseBody: String? {
        responseBody?.prettyBody
    }

    public var prettyRequestBody: String? {
        requestBody?.prettyBody
    }
}

extension Data {
    /// This body as pretty-printed JSON with sorted keys, or as UTF-8 text when it isn't JSON.
    var prettyBody: String? {
        if let json = try? JSONSerialization.jsonObject(with: self),
           let pretty = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
           let text = String(data: pretty, encoding: .utf8) {
            return text
        }
        return String(data: self, encoding: .utf8)
    }
}

/// A response body the log holds, with the text its filter searches.
struct NetworkResponseBody: Sendable {
    /// The bytes kept: the whole body, or its first bytes.
    let data: Data
    /// How many bytes the body had, all told; at least `data.count`.
    let size: Int
    /// The body as the detail shows it (pretty-printed JSON, or UTF-8 text), lowercased for a
    /// filter that ignores case; `nil` for a body that isn't text.
    let searchText: String?

    /// Parses and pretty-prints `data` once, here, so filtering the log never does.
    ///
    /// - Parameters:
    ///   - data: The bytes kept.
    ///   - size: How many bytes the body had, when more than `data` holds; `nil`, or a size
    ///     smaller than `data`, means `data` is all of it.
    init(_ data: Data, size: Int? = nil) {
        self.data = data
        self.size = max(size ?? data.count, data.count)
        searchText = data.prettyBody?.lowercased()
    }
}

/// How a request ended: what came back and how long it took, or why it failed.
struct NetworkCompletion {
    var statusCode: Int?
    var headers: [String: String]?
    var body: NetworkResponseBody?
    var duration: TimeInterval?
    var error: String?
}

extension NetworkEntry {
    /// What the request costs the log's byte bound: its body and its response's as the log kept
    /// them, with the response's search text, which holds the body again.
    var capturedByteCount: Int {
        (requestBody?.count ?? 0) + (response?.data.count ?? 0) + (response?.searchText?.utf8.count ?? 0)
    }
}
