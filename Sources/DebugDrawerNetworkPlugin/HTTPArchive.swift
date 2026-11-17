#if DEBUG
    import DebugDrawer
    import Foundation

    /// An HTTP Archive (HAR 1.2), the format browsers' network inspectors export and import:
    /// http://www.softwareishard.com/blog/har-12-spec/
    ///
    /// Only what the plugin captures is filled in; sizes it doesn't know are `-1`, as the format
    /// asks.
    struct HTTPArchive: Encodable, Equatable {
        struct Log: Encodable, Equatable {
            var version = "1.2"
            var creator = Creator()
            var entries: [Entry]
        }

        struct Creator: Encodable, Equatable {
            var name = "DebugDrawer"
            var version = "1.0"
        }

        struct NameValue: Encodable, Equatable {
            var name: String
            var value: String
        }

        struct PostData: Encodable, Equatable {
            var mimeType: String
            var text: String
        }

        struct Request: Encodable, Equatable {
            var method: String
            var url: String
            var httpVersion: String
            var cookies: [NameValue] = []
            var headers: [NameValue]
            var queryString: [NameValue]
            var postData: PostData?
            var headersSize = -1
            var bodySize: Int
        }

        struct Content: Encodable, Equatable {
            var size: Int
            var mimeType: String
            var text: String?
            var encoding: String?
        }

        struct Response: Encodable, Equatable {
            var status: Int
            var statusText: String
            var httpVersion: String
            var cookies: [NameValue] = []
            var headers: [NameValue]
            var content: Content
            var redirectURL = ""
            var headersSize = -1
            var bodySize: Int
        }

        /// Milliseconds per phase; `-1` for a phase that didn't happen or wasn't measured.
        struct Timings: Encodable, Equatable {
            var blocked = -1.0
            var dns: Double
            var connect: Double
            var ssl: Double
            var send: Double
            var wait: Double
            var receive: Double
        }

        struct Entry: Encodable, Equatable {
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
        }

        struct Cache: Encodable, Equatable {}

        var log: Log
    }

    // Declared in an extension so the type nests one level deep, not two.
    extension HTTPArchive.Entry {
        enum CodingKeys: String, CodingKey {
            case startedDateTime, time, request, response, cache, timings, comment
            case error = "_error"
        }
    }

    extension HTTPArchive {
        /// The archive of `entries`, oldest first, with every value `redaction` calls sensitive
        /// masked: header values, URL query items, and values in JSON bodies.
        init(_ entries: [NetworkEntry], redaction: DebugDrawerRedaction) {
            let byID = Dictionary(entries.map { ($0.id, $0) }) { first, _ in first }
            log = Log(entries: entries.sorted { $0.timestamp < $1.timestamp }.map { entry in
                Entry(entry, original: entry.replayOf.flatMap { byID[$0] }, redaction: redaction)
            })
        }
    }

    extension HTTPArchive.Entry {
        /// - Parameter original: The request `entry` resends, when it is a replay and the
        ///   original is in the archive.
        fileprivate init(_ entry: NetworkEntry, original: NetworkEntry?, redaction: DebugDrawerRedaction) {
            let url = redaction.redacting(url: entry.url)
            let httpVersion = entry.metrics?.protocolName.map(HTTPArchive.httpVersion) ?? "HTTP/1.1"
            let requestHeaders = redaction.redacting(headers: entry.requestHeaders)
            let responseHeaders = redaction.redacting(headers: entry.responseHeaders ?? [:])
            let requestBody = entry.requestBody.map { redaction.redacting(json: $0) }
            let responseBody = entry.responseBody.map { redaction.redacting(json: $0) }
            let time = (entry.duration ?? 0) * 1000

            startedDateTime = HTTPArchive.dateStyle.format(entry.timestamp)
            self.time = time
            request = HTTPArchive.Request(
                method: entry.method,
                url: url,
                httpVersion: httpVersion,
                headers: requestHeaders.harNameValues,
                queryString: (URLComponents(string: url)?.queryItems ?? []).map {
                    HTTPArchive.NameValue(name: $0.name, value: $0.value ?? "")
                },
                postData: requestBody.map {
                    HTTPArchive.PostData(
                        mimeType: requestHeaders.value(named: "Content-Type") ?? "",
                        text: String(bytes: $0, encoding: .utf8) ?? $0.base64EncodedString()
                    )
                },
                bodySize: entry.requestBody?.count ?? 0
            )
            // HAR carries a body that isn't text in base64, and says so.
            let responseText = responseBody.flatMap { String(bytes: $0, encoding: .utf8) }
            let isBinary = responseBody != nil && responseText == nil
            response = HTTPArchive.Response(
                status: entry.statusCode ?? 0,
                statusText: entry.statusCode.map { HTTPURLResponse.localizedString(forStatusCode: $0) } ?? "",
                httpVersion: httpVersion,
                headers: responseHeaders.harNameValues,
                content: HTTPArchive.Content(
                    size: entry.responseBody?.count ?? 0,
                    mimeType: responseHeaders.value(named: "Content-Type") ?? "",
                    text: responseText ?? responseBody?.base64EncodedString(),
                    encoding: isBinary ? "base64" : nil
                ),
                bodySize: entry.responseBody?.count ?? (entry.isComplete ? 0 : -1)
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
        fileprivate static let dateStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

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
