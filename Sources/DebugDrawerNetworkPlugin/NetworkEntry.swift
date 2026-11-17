#if DEBUG
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
        public let requestBody: Data?
        public var statusCode: Int?
        public var responseHeaders: [String: String]?
        public var responseBody: Data?
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
            statusCode: Int? = nil,
            responseHeaders: [String: String]? = nil,
            responseBody: Data? = nil,
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
            self.statusCode = statusCode
            self.responseHeaders = responseHeaders
            self.responseBody = responseBody
            self.duration = duration
            self.error = error
            self.isComplete = isComplete
            self.metrics = metrics
            self.mockRuleName = mockRuleName
            self.conditionEffect = conditionEffect
            self.replayOf = replayOf
            // Worked out here, once, as the request's fields never change: the log reads it on
            // every render and every keystroke in the filter.
            graphQLOperationName = Self.graphQLOperationName(method: method, url: url, body: requestBody)
        }

        /// Whether the request failed: the server answered with a status of 400 or more, or the
        /// request never got an answer (a transport error).
        var isFailure: Bool {
            error != nil || (statusCode ?? 0) >= 400
        }

        public var responseSizeLabel: String {
            guard let data = responseBody else { return "—" }
            if data.count < 1024 { return "\(data.count) B" }
            if data.count < 1024 * 1024 { return "\(data.count / 1024) KB" }
            return String(format: "%.1f MB", Double(data.count) / (1024 * 1024))
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

    /// How a request ended: what came back and how long it took, or why it failed.
    struct NetworkCompletion {
        var statusCode: Int?
        var headers: [String: String]?
        var body: Data?
        var duration: TimeInterval?
        var error: String?
    }
#endif
