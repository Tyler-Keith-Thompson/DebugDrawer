#if DEBUG
    import DebugDrawer
    import Foundation

    extension NetworkEntry {
        /// The request as a cURL command, with every value the rules call sensitive masked: in
        /// the URL's query, the headers and a JSON body.
        func curl(redaction: DebugDrawerRedaction) -> String {
            var parts = ["curl"]

            if method != "GET" {
                parts.append("-X \(method)")
            }

            parts.append("'\(redaction.redacting(url: url).shellQuoted)'")

            for (key, value) in redaction.redacting(headers: requestHeaders).sorted(by: { $0.key < $1.key }) {
                parts.append("-H '\(key): \(value.shellQuoted)'")
            }

            if let requestBody = redactedRequestBody(redaction),
               let body = String(data: requestBody, encoding: .utf8),
               !body.isEmpty {
                parts.append("-d '\(body.shellQuoted)'")
            }

            return parts.joined(separator: " \\\n  ")
        }
    }

    extension String {
        /// This text inside single quotes in a POSIX shell: each `'` closes the quote, adds an
        /// escaped quote and reopens it.
        fileprivate var shellQuoted: String {
            replacingOccurrences(of: "'", with: "'\\''")
        }
    }
#endif
