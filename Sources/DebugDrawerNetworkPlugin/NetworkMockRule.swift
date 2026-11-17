#if DEBUG
    import Foundation

    /// A canned response for the requests a matcher picks: once `installNetwork()` has run, a
    /// request the first enabled rule matches is answered from the rule, without reaching the
    /// network, and shows as mocked in the Network plugin's log.
    ///
    /// Rules are kept in a list the drawer orders; the first enabled rule that matches answers.
    /// A request that no rule matches reaches the network unchanged.
    ///
    /// ```swift
    /// let greeting = NetworkMockRule(
    ///     name: "Greeting",
    ///     matcher: .init(methods: ["GET"], host: .exact("api.example.com"), path: .wildcard("/v1/greeting/*")),
    ///     response: .init(status: 200, body: .text(#"{"message":"Hello"}"#), contentType: "application/json")
    /// )
    /// ```
    public struct NetworkMockRule: Identifiable, Hashable, Codable, Sendable {
        /// The rule's identity, which an edit keeps.
        public var id: UUID
        /// What the drawer lists the rule as, and the log names it by.
        public var name: String
        /// Whether the rule answers requests; a disabled one is skipped.
        public var isEnabled: Bool
        /// Which requests the rule answers.
        public var matcher: Matcher
        /// What the rule answers them with.
        public var response: Response

        /// - Parameters:
        ///   - id: The rule's identity; a rule passed to `installNetwork(mocks:)` keeps one id from
        ///     launch to launch, so it is added once.
        ///   - name: What the drawer lists the rule as.
        ///   - isEnabled: Whether the rule answers requests.
        ///   - matcher: Which requests it answers.
        ///   - response: What it answers them with.
        public init(id: UUID = UUID(), name: String, isEnabled: Bool = true, matcher: Matcher, response: Response) {
            self.id = id
            self.name = name
            self.isEnabled = isEnabled
            self.matcher = matcher
            self.response = response
        }
    }

    public extension NetworkMockRule {
        /// Which requests a rule answers: every part must match.
        struct Matcher: Hashable, Sendable {
            /// The methods matched, compared without regard to case; empty matches any method.
            public var methods: Set<String>
            /// The URL's host, compared without regard to case. In a wildcard, `*` matches within
            /// one label (`*.example.com` matches `api.example.com`) and `**` across labels.
            public var host: Pattern
            /// The URL's path, percent-decoded, `/` when empty. In a wildcard, `*` matches within
            /// one segment (`/users/*`) and `**` across segments (`/users/**`).
            public var path: Pattern
            /// Query items the URL must carry with exactly these values; items it carries beyond
            /// them don't matter. Empty matches any query.
            public var query: [String: String]

            /// - Parameters:
            ///   - methods: The methods matched; empty for any.
            ///   - host: The host's pattern.
            ///   - path: The path's pattern.
            ///   - query: Query items the URL must carry.
            public init(methods: Set<String> = [], host: Pattern = .any, path: Pattern = .any, query: [String: String] = [:]) {
                self.methods = Set(methods.map { $0.uppercased() })
                self.host = host
                self.path = path
                self.query = query
            }
        }

        /// How a matcher compares a host or a path.
        ///
        /// A wildcard and a regular expression match the whole host or path, as if anchored at
        /// both ends.
        enum Pattern: Hashable, Sendable {
            /// Matches anything.
            case any
            /// Matches this text alone.
            case exact(String)
            /// Matches a glob: `*` within one label or segment, `**` across them.
            case wildcard(String)
            /// Matches an `NSRegularExpression` pattern.
            case regex(String)
        }

        /// What a rule answers with.
        ///
        /// The response is sent as it stands; a later field (a delay, say) decodes as absent from
        /// files written before it.
        struct Response: Hashable, Codable, Sendable {
            /// The HTTP status code.
            public var status: Int
            /// The response's headers. `Content-Length` is always the body's length, whatever is
            /// given here.
            public var headers: [String: String]
            /// The response's body.
            public var body: Body
            /// The `Content-Type`, which replaces one in `headers`; `nil` keeps the headers' own,
            /// or for a file body, the type its extension names.
            public var contentType: String?

            /// - Parameters:
            ///   - status: The HTTP status code.
            ///   - headers: The response's headers.
            ///   - body: The response's body.
            ///   - contentType: The `Content-Type`; `nil` keeps the headers' own.
            public init(status: Int = 200, headers: [String: String] = [:], body: Body = .empty, contentType: String? = nil) {
                self.status = status
                self.headers = headers
                self.body = body
                self.contentType = contentType
            }
        }

        /// A response's body.
        enum Body: Hashable, Sendable {
            /// No body.
            case empty
            /// Text, sent as UTF-8.
            case text(String)
            /// A file in the plugin's storage, by name: one chosen in the editor is copied there.
            case file(String)
        }
    }

    // MARK: - Coding

    // Enums with payloads are written as a `kind` and its value, which reads better in the file
    // than the synthesized `{"exact": {"_0": …}}` and keeps one shape as cases are added.

    extension NetworkMockRule.Matcher: Codable {
        private enum CodingKeys: String, CodingKey {
            case methods, host, path, query
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(
                methods: Set(container.decodeIfPresent([String].self, forKey: .methods) ?? []),
                host: container.decodeIfPresent(NetworkMockRule.Pattern.self, forKey: .host) ?? .any,
                path: container.decodeIfPresent(NetworkMockRule.Pattern.self, forKey: .path) ?? .any,
                query: container.decodeIfPresent([String: String].self, forKey: .query) ?? [:]
            )
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            // Sorted, so the file doesn't change from one save to the next.
            try container.encode(methods.sorted(), forKey: .methods)
            try container.encode(host, forKey: .host)
            try container.encode(path, forKey: .path)
            try container.encode(query, forKey: .query)
        }
    }

    extension NetworkMockRule.Pattern: Codable {
        private enum CodingKeys: String, CodingKey {
            case kind, value
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let kind = try container.decode(String.self, forKey: .kind)
            switch kind {
            case "any": self = .any
            case "exact": self = try .exact(container.decode(String.self, forKey: .value))
            case "wildcard": self = try .wildcard(container.decode(String.self, forKey: .value))
            case "regex": self = try .regex(container.decode(String.self, forKey: .value))
            default:
                throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "Unknown pattern kind \(kind)")
            }
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .any:
                try container.encode("any", forKey: .kind)
            case let .exact(value):
                try container.encode("exact", forKey: .kind)
                try container.encode(value, forKey: .value)
            case let .wildcard(value):
                try container.encode("wildcard", forKey: .kind)
                try container.encode(value, forKey: .value)
            case let .regex(value):
                try container.encode("regex", forKey: .kind)
                try container.encode(value, forKey: .value)
            }
        }
    }

    extension NetworkMockRule.Body: Codable {
        private enum CodingKeys: String, CodingKey {
            case kind, text, file
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let kind = try container.decode(String.self, forKey: .kind)
            switch kind {
            case "empty": self = .empty
            case "text": self = try .text(container.decode(String.self, forKey: .text))
            case "file": self = try .file(container.decode(String.self, forKey: .file))
            default:
                throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "Unknown body kind \(kind)")
            }
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .empty:
                try container.encode("empty", forKey: .kind)
            case let .text(text):
                try container.encode("text", forKey: .kind)
                try container.encode(text, forKey: .text)
            case let .file(name):
                try container.encode("file", forKey: .kind)
                try container.encode(name, forKey: .file)
            }
        }
    }
#endif
