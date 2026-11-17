#if DEBUG
    import Foundation

    /// A slow or failing network for one host, or for every host: once `installNetwork()` has run,
    /// a request the first enabled profile matches waits out the profile's latency, may fail with
    /// its error, and otherwise gets its answer (a mock's or the server's) no faster than its
    /// bandwidth allows. The Network plugin's log marks each request a profile conditioned.
    ///
    /// Profiles are kept in a list the drawer orders; the first enabled profile whose host matches
    /// applies. A request to a host no profile matches is untouched.
    ///
    /// ```swift
    /// let slowImages = NetworkConditionProfile(
    ///     name: "Slow images",
    ///     host: .wildcard("*.cdn.example.com"),
    ///     latency: .seconds(2),
    ///     bandwidth: 50_000
    /// )
    /// ```
    public struct NetworkConditionProfile: Identifiable, Hashable, Sendable {
        /// The profile's identity, which an edit keeps.
        public var id: UUID
        /// What the drawer lists the profile as, and the log names it by.
        public var name: String
        /// Whether the profile applies; a disabled one is skipped.
        public var isEnabled: Bool
        /// The hosts the profile applies to: `.any` for every host. Compared as a mock rule's host
        /// is, without regard to case, a wildcard or regex matching the whole host.
        public var host: NetworkMockRule.Pattern
        /// How long a request waits before it is answered or sent. A negative latency is none.
        public var latency: Duration
        /// The most bytes a second the response's body arrives at, or `nil` for no cap. A cap of
        /// zero or less is none.
        public var bandwidth: Int?
        /// The share of requests, in percent, that fail with ``failure``: 0 never, 100 always.
        /// Above 100 acts as 100, and below 0 as 0.
        public var failureRate: Int
        /// How a request the profile fails ends.
        public var failure: Failure

        /// - Parameters:
        ///   - id: The profile's identity; a profile passed to `installNetwork(conditions:)` keeps
        ///     one id from launch to launch, so it is added once.
        ///   - name: What the drawer lists the profile as.
        ///   - isEnabled: Whether the profile applies.
        ///   - host: The hosts it applies to; `.any` for every host.
        ///   - latency: How long a request waits before it is answered or sent.
        ///   - bandwidth: The most bytes a second the response's body arrives at; `nil` for no cap.
        ///   - failureRate: The share of requests, in percent, that fail.
        ///   - failure: How a request that fails ends.
        public init(
            id: UUID = UUID(),
            name: String,
            isEnabled: Bool = true,
            host: NetworkMockRule.Pattern = .any,
            latency: Duration = .zero,
            bandwidth: Int? = nil,
            failureRate: Int = 0,
            failure: Failure = .timedOut
        ) {
            self.id = id
            self.name = name
            self.isEnabled = isEnabled
            self.host = host
            self.latency = latency
            self.bandwidth = bandwidth
            self.failureRate = failureRate
            self.failure = failure
        }
    }

    public extension NetworkConditionProfile {
        /// How a request a profile fails ends, named after the `URLError` code it fails with.
        enum Failure: String, CaseIterable, Hashable, Codable, Sendable {
            /// The request fails with `URLError(.timedOut)`.
            case timedOut
            /// The request fails with `URLError(.notConnectedToInternet)`.
            case notConnectedToInternet
            /// The request gets a response with status 500 and an empty body.
            case internalServerError
        }
    }

    // MARK: - Coding

    // The latency is written in whole milliseconds, which reads better in the file than Duration's
    // own seconds-and-attoseconds pair; fields a later format adds decode as absent from older files.

    extension NetworkConditionProfile: Codable {
        private enum CodingKeys: String, CodingKey {
            case id, name, isEnabled, host, latencyMilliseconds, bandwidth, failureRate, failure
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(
                id: container.decode(UUID.self, forKey: .id),
                name: container.decode(String.self, forKey: .name),
                isEnabled: container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true,
                host: container.decodeIfPresent(NetworkMockRule.Pattern.self, forKey: .host) ?? .any,
                latency: .milliseconds(container.decodeIfPresent(Int64.self, forKey: .latencyMilliseconds) ?? 0),
                bandwidth: container.decodeIfPresent(Int.self, forKey: .bandwidth),
                failureRate: container.decodeIfPresent(Int.self, forKey: .failureRate) ?? 0,
                failure: container.decodeIfPresent(Failure.self, forKey: .failure) ?? .timedOut
            )
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
            try container.encode(isEnabled, forKey: .isEnabled)
            try container.encode(host, forKey: .host)
            try container.encode(latency.milliseconds, forKey: .latencyMilliseconds)
            try container.encodeIfPresent(bandwidth, forKey: .bandwidth)
            try container.encode(failureRate, forKey: .failureRate)
            try container.encode(failure, forKey: .failure)
        }
    }

    extension Duration {
        /// The duration in whole milliseconds, rounded toward zero; past what an `Int64` holds,
        /// its largest or smallest value.
        var milliseconds: Int64 {
            let (seconds, attoseconds) = components
            guard seconds < Int64.max / 1000 else { return .max }
            guard seconds > Int64.min / 1000 else { return .min }
            return seconds * 1000 + attoseconds / 1_000_000_000_000_000
        }
    }
#endif
