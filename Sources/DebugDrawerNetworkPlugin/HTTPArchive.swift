#if DEBUG
    import DebugDrawer
    import Foundation

    /// An HTTP Archive (HAR 1.2), the format browsers' network inspectors export and import:
    /// http://www.softwareishard.com/blog/har-12-spec/
    ///
    /// Only what the plugin captures is filled in; sizes it doesn't know are `-1`, as the format
    /// asks. It reads the archives other tools write too, which leave out fields the format calls
    /// optional and add their own (`HTTPArchive+Decoding.swift`).
    struct HTTPArchive: Codable, Equatable {
        struct Log: Codable, Equatable {
            var version = "1.2"
            var creator = Creator()
            var entries: [Entry]
        }

        struct Creator: Codable, Equatable {
            var name = "DebugDrawer"
            var version = "1.0"
        }

        struct NameValue: Codable, Equatable {
            var name: String
            var value: String
        }

        /// A cookie a request sent or a response set; the attributes are a response's only.
        struct Cookie: Codable, Equatable {
            var name: String
            var value: String
            var path: String?
            var domain: String?
            /// When the cookie expires, in ISO 8601; `nil` for one that lasts the session.
            var expires: String?
            var httpOnly: Bool?
            var secure: Bool?
        }

        struct PostData: Codable, Equatable {
            var mimeType: String
            var text: String
            /// `base64` for a body that isn't text, whose `text` is then its base64. The format has
            /// no such field for a request body, so it is a custom field, `_encoding`.
            var encoding: String?
        }

        struct Request: Codable, Equatable {
            var method: String
            var url: String
            var httpVersion: String
            var cookies: [Cookie] = []
            var headers: [NameValue]
            var queryString: [NameValue]
            var postData: PostData?
            var headersSize = -1
            var bodySize: Int
        }

        struct Content: Codable, Equatable {
            var size: Int
            var mimeType: String
            var text: String?
            var encoding: String?
        }

        struct Response: Codable, Equatable {
            var status: Int
            var statusText: String
            var httpVersion: String
            var cookies: [Cookie] = []
            var headers: [NameValue]
            var content: Content
            var redirectURL = ""
            var headersSize = -1
            var bodySize: Int
        }

        /// Milliseconds per phase; `-1` for a phase that didn't happen or wasn't measured.
        struct Timings: Codable, Equatable {
            var blocked = -1.0
            var dns: Double
            var connect: Double
            var ssl: Double
            var send: Double
            var wait: Double
            var receive: Double
        }

        struct Entry: Codable, Equatable {
            var startedDateTime: String
            var time: Double
            var request: Request
            var response: Response
            var cache = Cache()
            var timings: Timings
            /// Why the request failed, in the format's convention for custom fields.
            var error: String?
            /// Which captured request this one resends, which mock rule answered it, and which
            /// conditioning profile slowed or failed it and how, when any did.
            var comment: String?
            /// `websocket` for a WebSocket connection, in Chrome DevTools' custom field
            /// `_resourceType`; `nil` for a request.
            var resourceType: String?
            /// A WebSocket connection's messages, in Chrome DevTools' custom field
            /// `_webSocketMessages`; `nil` for a request.
            var webSocketMessages: [WebSocketMessage]?
        }

        /// A WebSocket message, as Chrome DevTools writes it in `_webSocketMessages`.
        struct WebSocketMessage: Codable, Equatable {
            /// `send` or `receive`.
            var type: String
            /// When it went, in seconds since 1970.
            var time: Double
            /// 1 for text, 2 for binary.
            var opcode: Int
            /// The text, or a binary message's base64.
            var data: String
        }

        struct Cache: Codable, Equatable {}

        var log: Log
    }

    // Declared in an extension so the type nests one level deep, not two.
    extension HTTPArchive.Entry {
        enum CodingKeys: String, CodingKey {
            case startedDateTime, time, request, response, cache, timings, comment
            case error = "_error"
            case resourceType = "_resourceType"
            case webSocketMessages = "_webSocketMessages"
        }
    }

    extension HTTPArchive.PostData {
        enum CodingKeys: String, CodingKey {
            case mimeType, text
            case encoding = "_encoding"
        }
    }

    extension HTTPArchive {
        /// The archive of `entries` and of the WebSocket connections `webSockets`, oldest first,
        /// with every value `redaction` calls sensitive masked: header values, URL query items,
        /// and values in JSON bodies and JSON text messages.
        init(_ entries: [NetworkEntry], webSockets: [NetworkWebSocketConnection] = [], redaction: DebugDrawerRedaction) {
            let byID = Dictionary(entries.map { ($0.id, $0) }) { first, _ in first }
            let requests = entries.map { entry in
                Dated(start: entry.timestamp, entry: Entry(entry, original: entry.replayOf.flatMap { byID[$0] }, redaction: redaction))
            }
            let connections = webSockets.map { Dated(start: $0.opened, entry: Entry($0, redaction: redaction)) }
            log = Log(entries: (requests + connections).sorted { $0.start < $1.start }.map(\.entry))
        }

        /// An entry and when it started, to sort by.
        private struct Dated {
            var start: Date
            var entry: Entry
        }
    }

    extension HTTPArchive.Entry {
        /// - Parameter original: The request `entry` resends, when it is a replay and the
        ///   original is in the archive.
        init(_ entry: NetworkEntry, original: NetworkEntry?, redaction: DebugDrawerRedaction) {
            let url = redaction.redacting(url: entry.url)
            let httpVersion = entry.metrics?.protocolName.map(HTTPArchive.httpVersion) ?? "HTTP/1.1"
            let requestCookies = HTTPArchive.requestCookies(in: entry.requestHeaders)
            let responseCookies = HTTPArchive.responseCookies(in: entry.responseHeaders ?? [:], url: entry.url)
            let requestHeaders = redaction.redacting(headers: entry.requestHeaders, cookies: requestCookies)
            let responseHeaders = redaction.redacting(headers: entry.responseHeaders ?? [:], cookies: responseCookies)
            let requestBody = entry.redactedRequestBody(redaction)
            let responseBody = entry.redactedResponseBody(redaction)
            let time = (entry.duration ?? 0) * 1000

            startedDateTime = HTTPArchive.dateStyle.format(entry.timestamp)
            self.time = time
            request = HTTPArchive.Request(
                method: entry.method,
                url: url,
                httpVersion: httpVersion,
                cookies: requestCookies.map { redaction.redacting($0, header: "Cookie") },
                headers: requestHeaders.harNameValues,
                queryString: (URLComponents(string: url)?.queryItems ?? []).map {
                    HTTPArchive.NameValue(name: $0.name, value: $0.value ?? "")
                },
                postData: requestBody.map { body in
                    let text = String(bytes: body, encoding: .utf8)
                    return HTTPArchive.PostData(
                        mimeType: requestHeaders.value(named: "Content-Type") ?? "",
                        text: text ?? body.base64EncodedString(),
                        encoding: text == nil ? "base64" : nil
                    )
                },
                bodySize: entry.requestBodySize ?? 0
            )
            // HAR carries a body that isn't text in base64, and says so.
            let responseText = responseBody.flatMap { String(bytes: $0, encoding: .utf8) }
            let isBinary = responseBody != nil && responseText == nil
            response = HTTPArchive.Response(
                status: entry.statusCode ?? 0,
                statusText: entry.statusCode.map { HTTPURLResponse.localizedString(forStatusCode: $0) } ?? "",
                httpVersion: httpVersion,
                cookies: responseCookies.map { redaction.redacting($0, header: "Set-Cookie") },
                headers: responseHeaders.harNameValues,
                content: HTTPArchive.Content(
                    size: entry.responseBodySize ?? 0,
                    mimeType: responseHeaders.value(named: "Content-Type") ?? "",
                    text: responseText ?? responseBody?.base64EncodedString(),
                    encoding: isBinary ? "base64" : nil
                ),
                bodySize: entry.responseBodySize ?? (entry.isComplete ? 0 : -1)
            )
            timings = HTTPArchive.Timings(entry.metrics, total: time)
            error = entry.error
            comment = Self.comment(on: entry, original: original, redaction: redaction)
        }

        /// What the plugin had to do with `entry`, in sentences: the request it resends, the mock
        /// that answered it and the profile that conditioned it; `nil` when none applies.
        private static func comment(on entry: NetworkEntry, original: NetworkEntry?, redaction: DebugDrawerRedaction) -> String? {
            let notes = [
                entry.replayOf.map { _ in
                    // HAR entries have no ids, so the original is named by what identifies it in
                    // the archive: its method, URL and start.
                    original.map {
                        "Replay of the \($0.method) \(redaction.redacting(url: $0.url)) started \(HTTPArchive.dateStyle.format($0.timestamp))"
                    } ?? "Replay of a request not in this archive"
                },
                entry.mockRuleName.map { "Answered by the network mock “\($0)”" },
                entry.conditionEffect.map { "Conditioned by “\($0.profileName)”: \($0.summary)" }
            ].compactMap(\.self)
            return notes.isEmpty ? nil : notes.joined(separator: ". ")
        }
    }

    extension HTTPArchive.Timings {
        /// The phases `metrics` measured, in milliseconds; without metrics the whole request
        /// counts as waiting, since send, wait and receive are required.
        fileprivate init(_ metrics: NetworkTimingMetrics?, total: Double) {
            func milliseconds(_ kind: NetworkTimingMetrics.Phase.Kind) -> Double? {
                metrics?.phases.first { $0.kind == kind }.map { $0.duration * 1000 }
            }
            dns = milliseconds(.dns) ?? -1
            connect = milliseconds(.connect) ?? -1
            ssl = milliseconds(.tls) ?? -1
            if metrics == nil {
                send = 0
                wait = total
                receive = 0
            } else {
                send = milliseconds(.request) ?? 0
                wait = milliseconds(.timeToFirstByte) ?? 0
                receive = milliseconds(.response) ?? 0
            }
        }
    }

    extension HTTPArchive {
        /// HAR's dates: ISO 8601 with milliseconds.
        static let dateStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

        /// The HTTP version HAR names for an ALPN protocol name (`h2` is `HTTP/2`).
        fileprivate static func httpVersion(_ protocolName: String) -> String {
            switch protocolName.lowercased() {
            case "h2": "HTTP/2"
            case "h3": "HTTP/3"
            case "http/1.0": "HTTP/1.0"
            default: "HTTP/1.1"
            }
        }
    }

    extension HTTPArchive {
        /// The cookies a `Cookie` header in `headers` sends.
        fileprivate static func requestCookies(in headers: [String: String]) -> [Cookie] {
            guard let header = headers.value(named: "Cookie") else { return [] }
            return header.split(separator: ";").compactMap { pair in
                let parts = pair.split(separator: "=", maxSplits: 1)
                guard let name = parts.first?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return nil }
                let value = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
                return Cookie(name: name, value: value)
            }
        }

        /// The cookies the `Set-Cookie` headers in `headers` set for `url`, with their attributes.
        fileprivate static func responseCookies(in headers: [String: String], url: String) -> [Cookie] {
            guard let url = URL(string: url), let header = headers.value(named: "Set-Cookie") else { return [] }
            return HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie": header], for: url).map { cookie in
                Cookie(
                    name: cookie.name,
                    value: cookie.value,
                    path: cookie.path,
                    domain: cookie.domain,
                    expires: cookie.expiresDate.map(dateStyle.format),
                    httpOnly: cookie.isHTTPOnly,
                    secure: cookie.isSecure
                )
            }
        }
    }

    extension DebugDrawerRedaction {
        /// The cookie with its value masked when the rules mask the header that carries it or a
        /// key in its name.
        fileprivate func redacting(_ cookie: HTTPArchive.Cookie, header: String) -> HTTPArchive.Cookie {
            var cookie = cookie
            if masksHeader(header) || masksKey(cookie.name) {
                cookie.value = Self.mask
            }
            return cookie
        }

        /// The headers with every sensitive header's value masked, and in the `Cookie` and
        /// `Set-Cookie` headers the rules leave, the value of each of `cookies` whose name they
        /// mask, so a cookie masked in the archive's cookie list doesn't show in its header.
        fileprivate func redacting(headers: [String: String], cookies: [HTTPArchive.Cookie]) -> [String: String] {
            let masked = cookies.filter { masksKey($0.name) && !$0.value.isEmpty }
            return redacting(headers: headers).reduce(into: [:]) { result, header in
                let carriesCookies = ["cookie", "set-cookie"].contains(header.key.lowercased())
                result[header.key] = carriesCookies
                    ? masked.reduce(header.value) { value, cookie in
                        value.replacing("\(cookie.name)=\(cookie.value)", with: "\(cookie.name)=\(Self.mask)")
                    }
                    : header.value
            }
        }
    }

    extension [String: String] {
        /// The headers as HAR's name-value pairs, sorted by name.
        fileprivate var harNameValues: [HTTPArchive.NameValue] {
            sorted { $0.key < $1.key }.map { HTTPArchive.NameValue(name: $0.key, value: $0.value) }
        }

        /// The value of the header named `name`, matched case-insensitively.
        fileprivate func value(named name: String) -> String? {
            first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
        }
    }
#endif
