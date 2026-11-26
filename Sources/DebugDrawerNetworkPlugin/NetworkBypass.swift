#if DEBUG
    import Foundation
    import os

    /// The hosts the app keeps out of interception, from `installNetwork(bypassing:)`: the URL
    /// protocol never takes their requests, so the app's own session sends them, and its delegate
    /// alone answers their TLS challenges; the plugin doesn't log, mock, condition or resend them,
    /// and doesn't record their WebSocket tasks.
    ///
    /// A host is matched as an ignored one is (``NetworkIgnoredDomain``): the domain and its
    /// subdomains, on label boundaries and ignoring case, or an IP address alone. The same type
    /// holds both lists, as the parsing and matching are the same; only what the plugin does with
    /// a match differs.
    enum NetworkBypass {
        /// Behind a lock rather than main-actor state: the URL protocol's `canInit` and the
        /// WebSocket factories read it synchronously, on whatever thread URL loading runs them.
        private static let domains = OSAllocatedUnfairLock<[NetworkIgnoredDomain]>(initialState: [])
        private static let logger = Logger(subsystem: "DebugDrawerNetworkPlugin", category: "NetworkBypass")

        /// The domains `hosts` name, to bypass.
        ///
        /// - Throws: `NetworkPlugin.InvalidInstallation.bypassedTextNotAHost` when one of `hosts`
        ///   isn't a host: an app that lists a host to keep it out of interception must not have it
        ///   intercepted over a typo. The log names the text and why.
        static func parse(_ hosts: [String]) throws(NetworkPlugin.InvalidInstallation) -> [NetworkIgnoredDomain] {
            var parsed: [NetworkIgnoredDomain] = []
            for text in hosts {
                do throws(NetworkIgnoredDomain.ParseError) {
                    try parsed.append(NetworkIgnoredDomain(parsing: text))
                } catch {
                    logger.error("installNetwork(bypassing:) can't bypass \(text, privacy: .public): \(error.message, privacy: .public)")
                    throw .bypassedTextNotAHost
                }
            }
            return parsed
        }

        /// Bypasses `domains` from now on, in place of the domains bypassed before.
        static func bypass(_ domains: [NetworkIgnoredDomain]) {
            self.domains.withLock { $0 = domains }
        }

        /// Whether `url`'s host is bypassed; `false` for a URL without a host.
        ///
        /// - Complexity: O(*d* × *n*) for *d* bypassed domains and a host of length *n*.
        static func covers(_ url: URL?) -> Bool {
            guard let host = url?.host else { return false }
            return domains.withLock { $0.ignores(host: host) }
        }
    }
#endif
