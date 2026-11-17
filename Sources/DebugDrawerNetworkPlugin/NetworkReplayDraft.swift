#if DEBUG
    import Foundation

    /// A captured request as the resend editor holds it while it is changed: its method, URL,
    /// headers and body as text, checked when sent. Made from a captured request, it describes
    /// that request exactly, so Resend sends it unchanged.
    struct NetworkReplayDraft: Equatable {
        /// The body to send.
        enum Body: Equatable {
            /// A body typed as text, sent as UTF-8; empty sends no body.
            case text(String)
            /// A captured body that isn't UTF-8 text, sent as captured; the editor can only remove
            /// it.
            case binary(Data)
        }

        /// Identifies the draft, so the editor of a new one starts from its own fields.
        let id = UUID()
        /// The captured request the draft resends.
        let original: NetworkEntry.ID
        var method: String
        var url: String
        var headers: [NetworkNameValue]
        var body: Body

        /// The editor's fields for `entry`: its method, URL, headers and body. `Content-Length`
        /// is left out, since the URL loading system sets it from the body sent.
        init(_ entry: NetworkEntry) {
            original = entry.id
            method = entry.method
            url = entry.url
            headers = [NetworkNameValue](sortedByName: entry.requestHeaders.filter { $0.key.lowercased() != "content-length" })
            body = if let data = entry.requestBody, !data.isEmpty {
                String(data: data, encoding: .utf8).map(Body.text) ?? .binary(data)
            } else {
                .text("")
            }
        }

        /// The methods the editor offers: the standard ones, and the request's own if it is
        /// another.
        var methods: [String] {
            NetworkMockDraft.standardMethods.contains(method) ? NetworkMockDraft.standardMethods : NetworkMockDraft.standardMethods + [method]
        }

        /// Whether the server may act on the request (a POST, PUT, PATCH, DELETE or any other
        /// method that isn't safe), so sending it again asks first.
        var needsConfirmation: Bool {
            !Self.isSafe(method)
        }

        /// Whether `method` is safe, in RFC 9110's sense: GET, HEAD, OPTIONS and TRACE only read.
        static func isSafe(_ method: String) -> Bool {
            ["GET", "HEAD", "OPTIONS", "TRACE"].contains(method.uppercased())
        }

        // MARK: Checking

        /// Why the URL can't be sent, or `nil` when it can.
        var urlProblem: String? {
            parsedURL == nil ? "Enter an http or https URL with a host." : nil
        }

        /// Why the body can't be sent, or `nil` when it can. The URL loading system refuses a GET
        /// or HEAD with a body, so the editor says so rather than letting the send fail.
        var bodyProblem: String? {
            guard hasBody, ["GET", "HEAD"].contains(method.uppercased()) else { return nil }
            return "A \(method.uppercased()) can't carry a body. Remove it, or choose another method."
        }

        /// The request the fields describe, or `nil` while one of them has a problem.
        var request: URLRequest? {
            guard let url = parsedURL, bodyProblem == nil else { return nil }
            var request = URLRequest(url: url)
            request.httpMethod = method
            for (name, value) in headers.dictionary.sorted(by: { $0.key < $1.key }) {
                request.setValue(value, forHTTPHeaderField: name)
            }
            request.httpBody = switch body {
            case let .text(text): text.isEmpty ? nil : Data(text.utf8)
            case let .binary(data): data
            }
            return request
        }

        private var hasBody: Bool {
            switch body {
            case let .text(text): !text.isEmpty
            case .binary: true
            }
        }

        /// The URL, when it is http or https and names a host.
        private var parsedURL: URL? {
            let trimmed = url.trimmingCharacters(in: .whitespaces)
            guard let components = URLComponents(string: trimmed),
                  let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
                  let host = components.host, !host.isEmpty else { return nil }
            return components.url
        }
    }
#endif
