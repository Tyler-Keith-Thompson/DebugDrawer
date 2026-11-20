import Foundation

// The allowlist is the host's, fixed when it makes the capability, and checked at every request
// against the request's own host, not against a rule's pattern: a pattern can be a wildcard or
// match any host, so only the request says where it goes. Exact hosts and domains alone, matched
// as cookies' domains are (RFC 6265, 5.1.3), so an entry can't be widened by the sidecar's input
// and reads as what it allows. Rejected: patterns in the allowlist (a host's `*.example.com` would
// reach more than it reads as, and `.any` would be one keystroke from allowing everything), and
// checking rules as they arrive (a wildcard rule can't be judged until a request names a host).

public extension NetworkMocking {
    /// A host the app allows a sidecar's rules to answer for: one host exactly, or a domain and
    /// every host under it. Hosts are compared without regard to case, and a trailing dot is
    /// ignored.
    ///
    /// ```swift
    /// let allowed: [NetworkMocking.AllowedHost] = [.exact("api.example.com"), .domain("staging.example.com")]
    /// ```
    enum AllowedHost: Hashable, Sendable {
        /// This host alone: `.exact("api.example.com")` allows `api.example.com`, and neither
        /// `example.com` nor `v2.api.example.com`. An empty host allows nothing.
        case exact(String)
        /// The domain and every host under it, as a cookie's domain matches: `.domain("example.com")`
        /// allows `example.com` and `api.example.com`, and not `badexample.com`. A leading dot is
        /// ignored; an empty domain allows nothing.
        case domain(String)

        /// Whether a request to `host` may be answered.
        ///
        /// - Parameter host: The request URL's host.
        /// - Returns: `true` when the entry allows it.
        package func allows(_ host: String) -> Bool {
            let host = Self.normalized(host)
            guard !host.isEmpty else { return false }
            switch self {
            case let .exact(allowed):
                let allowed = Self.normalized(allowed)
                return !allowed.isEmpty && host == allowed
            case let .domain(domain):
                var domain = Self.normalized(domain)
                if domain.hasPrefix(".") {
                    domain.removeFirst()
                }
                return !domain.isEmpty && (host == domain || host.hasSuffix("." + domain))
            }
        }

        /// `host` lowercased, less one trailing dot.
        private static func normalized(_ host: String) -> String {
            var host = host.lowercased()
            if host.hasSuffix(".") {
                host.removeLast()
            }
            return host
        }
    }
}

// Written as a `kind` and the host, as the mock rules' patterns are, rather than the synthesized
// `{"exact": {"_0": …}}`.

extension NetworkMocking.AllowedHost: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, host
    }

    /// Reads an entry written as its `kind` (`exact` or `domain`) and its `host`.
    ///
    /// - Parameter decoder: The decoder to read from.
    /// - Throws: `DecodingError` for another kind or a missing host.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        let host = try container.decode(String.self, forKey: .host)
        switch kind {
        case "exact": self = .exact(host)
        case "domain": self = .domain(host)
        default:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "Unknown allowed host kind \(kind)")
        }
    }

    /// Writes the entry as its `kind` and its `host`.
    ///
    /// - Parameter encoder: The encoder to write to.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .exact(host):
            try container.encode("exact", forKey: .kind)
            try container.encode(host, forKey: .host)
        case let .domain(host):
            try container.encode("domain", forKey: .kind)
            try container.encode(host, forKey: .host)
        }
    }
}
