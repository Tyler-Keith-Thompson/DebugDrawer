#if DEBUG
    import Foundation

    extension NetworkMockRule {
        /// A rule that answers requests like `entry` as the server did: its method, host and exact
        /// path, and the captured status, headers and body. A request still in flight, or one that
        /// failed, gets 200 and no body.
        ///
        /// The body is the captured text; a body that isn't UTF-8 is left for the caller to keep as
        /// a file (`binaryBody(of:)`).
        init(mocking entry: NetworkEntry, id: UUID = UUID()) {
            let url = URL(string: entry.url)
            // The path as the matcher reads it, which keeps a trailing slash `entry.path` drops.
            let path = url.map { $0.path(percentEncoded: false) }.flatMap { $0.isEmpty ? nil : $0 } ?? entry.path
            let body: Body = if let data = entry.responseBody, !data.isEmpty, let text = String(data: data, encoding: .utf8) {
                .text(text)
            } else {
                .empty
            }
            self.init(
                id: id,
                name: "\(entry.method) \(path)",
                matcher: Matcher(methods: [entry.method], host: .exact(url?.host() ?? entry.host), path: .exact(path)),
                response: Response(
                    status: entry.statusCode ?? 200,
                    headers: (entry.responseHeaders ?? [:]).filter { !Self.headersNotReplayed.contains($0.key.lowercased()) },
                    body: body
                )
            )
        }

        /// The captured body of `entry` when it isn't text, which `init(mocking:)` leaves out.
        static func binaryBody(of entry: NetworkEntry) -> Data? {
            guard let data = entry.responseBody, !data.isEmpty, String(data: data, encoding: .utf8) == nil else { return nil }
            return data
        }

        /// Headers that describe the bytes on the wire rather than the body the log holds: URLSession
        /// hands over the body decoded and whole, and a mock sends its own length.
        private static let headersNotReplayed: Set = ["content-length", "content-encoding", "transfer-encoding"]
    }
#endif
