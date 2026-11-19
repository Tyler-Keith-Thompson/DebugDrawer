#if DEBUG
    import Foundation

    /// An edited request to send again, as a value a command carries: `URLRequest` isn't `Codable`.
    struct NetworkReplayRequest: Codable, Equatable, Sendable {
        let url: URL
        let method: String
        let headers: [String: String]
        let body: Data?

        /// The parts of `request` that Edit and Resend sets; `nil` for a request with no URL.
        ///
        /// - Parameter request: The request the editor built.
        init?(_ request: URLRequest) {
            guard let url = request.url else { return nil }
            self.url = url
            method = request.httpMethod ?? "GET"
            headers = request.allHTTPHeaderFields ?? [:]
            body = request.httpBody
        }

        /// The request to send.
        var urlRequest: URLRequest {
            var request = URLRequest(url: url)
            request.httpMethod = method
            for (name, value) in headers.sorted(by: { $0.key < $1.key }) {
                request.setValue(value, forHTTPHeaderField: name)
            }
            request.httpBody = body
            return request
        }
    }
#endif
