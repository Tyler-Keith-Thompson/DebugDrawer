#if DEBUG
    import Foundation

    extension NetworkEntry {
        /// The request an archive's entry records, as the log shows a captured one: complete, with
        /// the response's status, headers and body, or the error it failed with.
        ///
        /// HTTP/2's pseudo-headers (`:authority`, `:path`), which Chrome DevTools lists among the
        /// headers, are left out, and a header listed more than once gets its values joined with
        /// commas, as `URLResponse` joins them. A status of 0 means no answer. What the archive
        /// doesn't say stays unknown: a start it can't read is the reference date.
        init(_ entry: HTTPArchive.Entry) {
            let components = URLComponents(string: entry.request.url)
            self.init(
                timestamp: HTTPArchive.date(entry.startedDateTime) ?? Date(timeIntervalSinceReferenceDate: 0),
                method: entry.request.method,
                url: entry.request.url,
                host: components?.host ?? "",
                path: components.map { $0.path.isEmpty ? "/" : $0.path } ?? entry.request.url,
                requestHeaders: entry.request.headers.headerFields,
                requestBody: entry.request.postData.flatMap { $0.text.isEmpty ? nil : Data(harText: $0.text, encoding: $0.encoding) },
                requestBodySize: entry.request.bodySize > 0 ? entry.request.bodySize : nil,
                statusCode: entry.response.status > 0 ? entry.response.status : nil,
                responseHeaders: entry.response.status > 0 ? entry.response.headers.headerFields : nil,
                responseBody: entry.response.content.text.flatMap { Data(harText: $0, encoding: entry.response.content.encoding) },
                responseBodySize: entry.response.content.size,
                duration: entry.time >= 0 ? entry.time / 1000 : nil,
                error: entry.error ?? (entry.response.status > 0 ? nil : "No response"),
                isComplete: true
            )
        }
    }

    extension HTTPArchive {
        /// The date in a HAR's ISO 8601 `startedDateTime`, with or without fractional seconds.
        static func date(_ text: String) -> Date? {
            (try? dateStyle.parse(text)) ?? (try? Date.ISO8601FormatStyle().parse(text))
        }
    }

    extension [HTTPArchive.NameValue] {
        /// The headers as a dictionary, without HTTP/2's pseudo-headers, the values of a name
        /// listed twice joined with commas.
        fileprivate var headerFields: [String: String] {
            filter { !$0.name.hasPrefix(":") }.reduce(into: [:]) { fields, header in
                fields[header.name] = fields[header.name].map { "\($0), \(header.value)" } ?? header.value
            }
        }
    }

    extension Data {
        /// A HAR body's bytes: `text` decoded from base64 when `encoding` says so, or as UTF-8.
        fileprivate init?(harText text: String, encoding: String?) {
            if encoding == "base64" {
                self.init(base64Encoded: text)
            } else {
                self.init(text.utf8)
            }
        }
    }
#endif
