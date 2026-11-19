#if DEBUG
    import Foundation
    import os

    /// A host or domain whose requests and WebSocket connections the log hides: the domain and
    /// every subdomain of it, matched on label boundaries and ignoring case, so `example.com`
    /// hides `example.com` and `cdn.example.com` but not `badexample.com`. An IP address hides
    /// that address alone.
    ///
    /// Plain domains only, without the mock rules' wildcards: a domain already covers its
    /// subdomains, which is what `*.example.com` would say, and a suffix comparison costs less per
    /// request than a pattern.
    struct NetworkIgnoredDomain: Hashable, Codable, Sendable {
        /// Why typed text isn't a host or domain.
        enum ParseError: Error, Equatable {
            /// Nothing but spaces.
            case empty
            /// A `*` wildcard, which a domain doesn't need.
            case wildcard
            /// Characters a host name can't hold, an empty or overlong label, or a malformed address.
            case malformed

            /// The problem in a sentence, under the field.
            var message: String {
                switch self {
                case .empty: "Enter a host or domain, such as example.com."
                case .wildcard: "Leave out the *: example.com covers its subdomains too."
                case .malformed: "Not a host: use letters, digits, hyphens and dots, such as cdn.example.com, or an IP address."
                }
            }
        }

        /// The domain as it is compared: lowercased, without a port, brackets or a trailing dot
        /// (`cdn.example.com`, `192.168.0.1`, `::1`).
        let name: String
        /// Whether `name` is an IP address, which matches itself alone.
        private let isAddress: Bool

        /// The domain in `text`, as a person types or pastes it: a host (`cdn.example.com`), a
        /// host and port (`localhost:8080`), an IP address (`10.0.0.1`, `[::1]`) or a URL, of
        /// which only the host is kept. Case and a trailing dot are ignored.
        ///
        /// - Throws: `ParseError.empty` for blank text, `.wildcard` for a `*`, and `.malformed`
        ///   for anything else that isn't a host.
        init(parsing text: String) throws(ParseError) {
            var host = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !host.isEmpty else { throw .empty }
            guard !host.contains("*") else { throw .wildcard }
            if let scheme = host.range(of: "://") {
                host = String(host[scheme.upperBound...])
            }
            // A path, query or fragment after the host, and the user information before it.
            if let end = host.firstIndex(where: { "/?#".contains($0) }) {
                host = String(host[..<end])
            }
            if let at = host.lastIndex(of: "@") {
                host = String(host[host.index(after: at)...])
            }
            host = try Self.removingPort(from: host)
            if host.hasSuffix(".") {
                host.removeLast()
            }
            if host.isIPv6Address || host.isIPv4Address {
                isAddress = true
            } else if host.isHostName {
                isAddress = false
            } else {
                throw .malformed
            }
            name = host
        }

        /// Whether the log hides a request to `host`: it is this domain or a subdomain of it, or
        /// for an address, this address. Case, brackets around an IPv6 address and a trailing dot
        /// are ignored.
        ///
        /// - Complexity: O(*n*) in the host's length.
        func matches(host: String) -> Bool {
            var host = host.lowercased()
            if host.hasPrefix("["), host.hasSuffix("]") {
                host = String(host.dropFirst().dropLast())
            }
            if host.hasSuffix(".") {
                host.removeLast()
            }
            guard !isAddress else { return host == name }
            return host == name || (host.hasSuffix(name) && host.dropLast(name.count).hasSuffix("."))
        }

        /// The domains a person can ignore a request to `host` by, the narrowest first: the host,
        /// then each parent domain down to the last two labels (`cdn.img.example.com`,
        /// `img.example.com`, `example.com`). An address or a one-label host offers itself alone;
        /// a host that isn't one offers nothing.
        ///
        /// Without the Public Suffix List the last two labels can be a public suffix (`co.uk`); the
        /// person picks from the choices, so this offers them rather than guess a registrable
        /// domain.
        static func choices(forHost host: String) -> [NetworkIgnoredDomain] {
            guard let domain = try? NetworkIgnoredDomain(parsing: host) else { return [] }
            guard !domain.isAddress else { return [domain] }
            let labels = domain.name.split(separator: ".")
            return (0 ..< max(labels.count - 1, 1)).compactMap { start in
                try? NetworkIgnoredDomain(parsing: labels[start...].joined(separator: "."))
            }
        }

        /// The domain in `text`, a host the app passed to `installNetwork(ignoring:)`; `nil`, after
        /// logging why, when it isn't one. Skipped rather than trapped on: a typo in a debug tool's
        /// setting shouldn't stop the app at launch.
        static func seed(_ text: String) -> NetworkIgnoredDomain? {
            do {
                return try NetworkIgnoredDomain(parsing: text)
            } catch {
                logger.error("Ignored host \(text, privacy: .public) skipped: \(error.message, privacy: .public)")
                return nil
            }
        }

        private static let logger = Logger(subsystem: "DebugDrawerNetworkPlugin", category: "NetworkIgnoredDomain")

        /// `host` without a port:`localhost:8080` is `localhost`, `[::1]:8080` and `[::1]` are
        /// `::1`, and a bare IPv6 address, of several colons, is kept whole.
        private static func removingPort(from host: String) throws(ParseError) -> String {
            if host.hasPrefix("[") {
                guard let close = host.firstIndex(of: "]") else { throw .malformed }
                let rest = host[host.index(after: close)...]
                guard rest.isEmpty || (rest.hasPrefix(":") && rest.dropFirst().isPort) else { throw .malformed }
                return String(host[host.index(after: host.startIndex) ..< close])
            }
            let parts = host.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 2 else { return host }
            guard parts[1].isPort else { throw .malformed }
            return String(parts[0])
        }
    }

    extension [NetworkIgnoredDomain] {
        /// Whether one of the domains hides a request to `host`.
        func ignores(host: String) -> Bool {
            contains { $0.matches(host: host) }
        }
    }

    extension StringProtocol {
        /// Whether this is a port: one to five digits.
        fileprivate var isPort: Bool {
            (1 ... 5).contains(count) && allSatisfy(\.isASCIIDigit)
        }

        /// Whether this is a host name: dot-separated labels of 1 to 63 ASCII letters, digits,
        /// hyphens and underscores, none starting or ending with a hyphen, in at most 253
        /// characters, not all labels numeric (that would be an IPv4 address or a malformed one).
        fileprivate var isHostName: Bool {
            guard (1 ... 253).contains(count) else { return false }
            let labels = split(separator: ".", omittingEmptySubsequences: false)
            let isWellFormed = labels.allSatisfy { label in
                (1 ... 63).contains(label.count)
                    && label.allSatisfy { $0.isASCIIDigit || ("a" ... "z").contains($0) || $0 == "-" || $0 == "_" }
                    && label.first != "-" && label.last != "-"
            }
            return isWellFormed && !labels.allSatisfy { $0.allSatisfy(\.isASCIIDigit) }
        }

        /// Whether this is an IPv4 address in dotted-decimal: four numbers of 0 to 255.
        fileprivate var isIPv4Address: Bool {
            let parts = split(separator: ".", omittingEmptySubsequences: false)
            return parts.count == 4 && parts.allSatisfy { part in
                (1 ... 3).contains(part.count) && part.allSatisfy(\.isASCIIDigit) && (Int(part) ?? 256) <= 255
            }
        }

        /// Whether this is an IPv6 address, as `inet_pton` reads one.
        fileprivate var isIPv6Address: Bool {
            guard contains(":") else { return false }
            var address = in6_addr()
            return inet_pton(AF_INET6, String(self), &address) == 1
        }
    }

    extension Character {
        /// Whether this is one of the ASCII digits 0 to 9.
        fileprivate var isASCIIDigit: Bool {
            ("0" ... "9").contains(self)
        }
    }
#endif
