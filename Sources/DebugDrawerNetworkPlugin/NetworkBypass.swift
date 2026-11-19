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

        /// Bypasses `hosts` from now on, in place of the hosts bypassed before.
        ///
        /// Traps on text that isn't a host, naming it and why: an app that lists a host to keep it
        /// out of interception must not have it intercepted over a typo, and the trap shows at the
        /// first debug launch.
        static func bypass(_ hosts: [String]) {
            let parsed = hosts.map { text -> NetworkIgnoredDomain in
                do throws(NetworkIgnoredDomain.ParseError) {
                    return try NetworkIgnoredDomain(parsing: text)
                } catch {
                    preconditionFailure("installNetwork(bypassing:) can't bypass \"\(text)\": \(error.message)")
                }
            }
            domains.withLock { $0 = parsed }
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
