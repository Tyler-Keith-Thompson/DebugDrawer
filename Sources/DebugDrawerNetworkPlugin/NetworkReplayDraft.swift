#if DEBUG
    import Foundation

    /// A captured request as the resend editor holds it while it is changed: its method, URL,
    /// headers and body as text, checked when sent. Made from a captured request, it describes
    /// that request exactly, so Resend sends it unchanged; when the log kept only the first bytes
    /// of its body, it holds them marked as cut, and sends nothing until the body is replaced or
    /// removed.
    struct NetworkReplayDraft: Equatable {
        /// The body to send.
        enum Body: Equatable {
            /// A body typed as text, sent as UTF-8; empty sends no body.
            case text(String)
            /// A captured body that isn't UTF-8 text, sent as captured; the editor can only remove
            /// it.
            case binary(Data)
            /// The first bytes of a captured body the log cut short, which had `size` bytes in
            /// all. It can't be sent: the editor can only edit the kept part as text, or remove it.
            case truncated(kept: Data, size: Int)
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
            body = if let data = entry.requestBody, entry.isRequestBodyTruncated {
                .truncated(kept: data, size: entry.requestBodySize ?? data.count)
            } else if let data = entry.requestBody, !data.isEmpty {
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

        /// Why `entry` can't be sent again unchanged, or `nil` when it can: the log kept only the
        /// first bytes of its body, and sending them would send a different request.
        static func resendProblem(of entry: NetworkEntry) -> String? {
            guard entry.isRequestBodyTruncated, let kept = entry.requestBody else { return nil }
            return "The log kept only the first \(NetworkEntry.sizeLabel(kept.count)) of its \(entry.requestSizeLabel) body. "
                + "Use Edit and Resend to replace or remove the body."
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

        /// Why the body can't be sent, or `nil` when it can. A body the log cut short isn't the
        /// request's, so it waits to be replaced or removed. The URL loading system refuses a GET
        /// or HEAD with a body, so the editor says so rather than letting the send fail.
        var bodyProblem: String? {
            if case .truncated = body {
                return "Only part of the body was kept, so it can't be sent. Edit the kept part, or remove the body."
            }
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
            // Never reached: `bodyProblem` refuses a cut body above.
            case .truncated: nil
            }
            return request
        }

        private var hasBody: Bool {
            switch body {
            case let .text(text): !text.isEmpty
            case .binary, .truncated: true
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
