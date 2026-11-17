#if DEBUG
    import Foundation

    /// Sends the requests the drawer resends.
    protocol NetworkReplaySender: Sendable {
        /// Sends `request` and returns once its answer has arrived whole.
        ///
        /// - Throws: Why no answer came, such as a `URLError` for a timeout or no connection. An
        ///   answer with an error status is an answer, not a throw.
        func send(_ request: URLRequest) async throws
    }

    /// Sends through a URL session whose configuration puts the plugin's URL protocol first, so a
    /// resent request is captured, mocked and conditioned like any the app makes.
    struct _NetworkReplaySender: NetworkReplaySender {
        let session: URLSession

        /// - Parameter session: The session to send through; by default one with the default
        ///   configuration (the app's shared cookies, cache and credentials) and the plugin's URL
        ///   protocol.
        init(session: URLSession = Self.interceptedSession()) {
            self.session = session
        }

        func send(_ request: URLRequest) async throws {
            _ = try await session.data(for: request)
        }

        /// A session with the default configuration, the plugin's URL protocol first. Named
        /// outright rather than left to `installNetwork()`'s swizzle, so a replay is captured
        /// however the plugin was installed.
        static func interceptedSession() -> URLSession {
            let configuration = URLSessionConfiguration.default
            let others = (configuration.protocolClasses ?? []).filter { $0 != DebugNetworkProtocol.self }
            configuration.protocolClasses = [DebugNetworkProtocol.self] + others
            return URLSession(configuration: configuration)
        }
    }
#endif
