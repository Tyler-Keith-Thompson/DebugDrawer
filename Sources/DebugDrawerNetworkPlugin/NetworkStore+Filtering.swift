#if DEBUG
    import Foundation

    extension NetworkStore {
        /// The requests in `entries` to a host none of `ignored` matches that pass the status
        /// filter `status` and contain `text` (ignoring case) in the URL, the method, the GraphQL
        /// operation name or the response body. Empty text matches every request. The body is
        /// searched as it was pretty-printed when it arrived.
        ///
        /// - Complexity: O(*n*) in the text of `entries`; no body is parsed.
        nonisolated static func entries(
            _ entries: [NetworkEntry],
            matching status: StatusFilter,
            text: String,
            ignoring ignored: [NetworkIgnoredDomain] = []
        ) -> [NetworkEntry] {
            var result = ignored.isEmpty ? entries : entries.filter { !ignored.ignores(host: $0.host) }
            switch status {
            case .all: break
            case .success: result = result.filter { ($0.statusCode ?? 0) >= 200 && ($0.statusCode ?? 0) < 300 }
            case .clientError: result = result.filter { ($0.statusCode ?? 0) >= 400 && ($0.statusCode ?? 0) < 500 }
            case .serverError: result = result.filter { ($0.statusCode ?? 0) >= 500 }
            case .errors: result = result.filter(\.isFailure)
            }
            if !text.isEmpty {
                let query = text.lowercased()
                result = result.filter {
                    $0.url.lowercased().contains(query) ||
                        $0.method.lowercased().contains(query) ||
                        ($0.graphQLOperationName?.lowercased().contains(query) ?? false) ||
                        ($0.response?.searchText?.contains(query) ?? false)
                }
            }
            return result
        }

        /// The connections in `connections` to a host none of `ignored` matches that pass the
        /// status filter `status` and contain `text` (ignoring case) in the URL, the method ("WS")
        /// or a text frame. A connection has no HTTP status, so All shows every one, Errors those
        /// that failed, and the others none.
        nonisolated static func connections(
            _ connections: [NetworkWebSocketConnection],
            matching status: StatusFilter,
            text: String,
            ignoring ignored: [NetworkIgnoredDomain] = []
        ) -> [NetworkWebSocketConnection] {
            var result = ignored.isEmpty ? connections : connections.filter { !ignored.ignores(host: $0.host) }
            switch status {
            case .all: break
            case .success, .clientError, .serverError: result = []
            case .errors: result = result.filter(\.isFailure)
            }
            if !text.isEmpty {
                let query = text.lowercased()
                result = result.filter { connection in
                    connection.url.lowercased().contains(query) || "ws".contains(query)
                        || connection.frames.contains { $0.text?.lowercased().contains(query) ?? false }
                }
            }
            return result
        }
    }
#endif
