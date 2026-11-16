#if DEBUG
    import DebugDrawer
    @testable import DebugDrawerNetworkPlugin
    import Foundation
    import Testing

    @Suite
    struct NetworkReportTests {
        @Test("The report gets network.har, a HAR 1.2 log with the request's method, URL, headers, query, body and the response")
        func harEntry() throws {
            var entry = NetworkEntry(
                timestamp: Date(timeIntervalSince1970: 1_800_000_000), method: "POST",
                url: "https://api.example.com/v1/orders?page=2", host: "api.example.com", path: "/v1/orders",
                requestHeaders: ["Content-Type": "application/json"], requestBody: Data(#"{"item":"tea"}"#.utf8),
                isComplete: true
            )
            entry.statusCode = 201
            entry.responseHeaders = ["Content-Type": "application/json"]
            entry.responseBody = Data(#"{"id":7}"#.utf8)
            entry.duration = 0.25
            var report = DebugDrawerReport()

            NetworkPlugin.contribute([entry], to: &report, redaction: .none)

            let file = try #require(report.files.first)
            let har = try #require(try JSONSerialization.jsonObject(with: file.data) as? [String: Any])
            let log = try #require(har["log"] as? [String: Any])
            let creator = try #require(log["creator"] as? [String: Any])
            let entries = try #require(log["entries"] as? [[String: Any]])
            let first = try #require(entries.first)
            let request = try #require(first["request"] as? [String: Any])
            let response = try #require(first["response"] as? [String: Any])
            let content = try #require(response["content"] as? [String: Any])
            let postData = try #require(request["postData"] as? [String: Any])
            let query = try #require(request["queryString"] as? [[String: String]])
            let headers = try #require(request["headers"] as? [[String: String]])
            let timings = try #require(first["timings"] as? [String: Double])
            #expect(file.name == "network.har")
            #expect(file.kind == .har)
            #expect(log["version"] as? String == "1.2")
            #expect(creator["name"] as? String == "DebugDrawer")
            #expect(entries.count == 1)
            #expect(first["startedDateTime"] as? String == "2027-01-15T08:00:00.000Z")
            #expect(first["time"] as? Double == 250)
            #expect(request["method"] as? String == "POST")
            #expect(request["url"] as? String == "https://api.example.com/v1/orders?page=2")
            #expect(query == [["name": "page", "value": "2"]])
            #expect(headers == [["name": "Content-Type", "value": "application/json"]])
            #expect(postData["mimeType"] as? String == "application/json")
            #expect(postData["text"] as? String == #"{"item":"tea"}"#)
            #expect(response["status"] as? Int == 201)
            #expect(content["size"] as? Int == 8)
            #expect(content["mimeType"] as? String == "application/json")
            #expect(content["text"] as? String == #"{"id":7}"#)
            #expect(timings["send"] == 0)
            #expect(timings["wait"] == 250)
            #expect(timings["receive"] == 0)
        }

        @Test("The HAR masks the Authorization header, a token query item and a JSON body's password")
        func harRedacted() throws {
            let entry = NetworkEntry(
                timestamp: Date(timeIntervalSince1970: 0), method: "POST",
                url: "https://api.example.com/login?token=t0k3n&lang=en", host: "api.example.com", path: "/login",
                requestHeaders: ["Authorization": "Bearer s3cr3t", "Accept": "application/json"],
                requestBody: Data(#"{"user":"ada","password":"hunter2"}"#.utf8),
                isComplete: false
            )
            var report = DebugDrawerReport()

            NetworkPlugin.contribute([entry], to: &report, redaction: .standard)

            let file = try #require(report.files.first)
            let text = try #require(String(bytes: file.data, encoding: .utf8))
            let har = try #require(try JSONSerialization.jsonObject(with: file.data) as? [String: Any])
            let log = try #require(har["log"] as? [String: Any])
            let entries = try #require(log["entries"] as? [[String: Any]])
            let request = try #require(entries.first?["request"] as? [String: Any])
            let headers = try #require(request["headers"] as? [[String: String]])
            let query = try #require(request["queryString"] as? [[String: String]])
            #expect(headers.contains(["name": "Authorization", "value": "[REDACTED]"]))
            #expect(headers.contains(["name": "Accept", "value": "application/json"]))
            #expect(query == [["name": "token", "value": "[REDACTED]"], ["name": "lang", "value": "en"]])
            #expect(!text.contains("s3cr3t"))
            #expect(!text.contains("t0k3n"))
            #expect(!text.contains("hunter2"))
        }

        @Test("The HAR lists requests oldest first, though the store keeps the newest first")
        func oldestFirst() throws {
            let newer = NetworkEntry(
                timestamp: Date(timeIntervalSince1970: 10), method: "GET", url: "https://example.com/b",
                host: "example.com", path: "/b", requestHeaders: [:], requestBody: nil, isComplete: false
            )
            let older = NetworkEntry(
                timestamp: Date(timeIntervalSince1970: 0), method: "GET", url: "https://example.com/a",
                host: "example.com", path: "/a", requestHeaders: [:], requestBody: nil, isComplete: false
            )
            let expected = ["https://example.com/a", "https://example.com/b"]

            let actual = HTTPArchive([newer, older], redaction: .none).log.entries.map(\.request.url)

            #expect(actual == expected)
        }

        @Test("Measured phases become the HAR's timings in milliseconds; unmeasured optional ones are -1")
        func timingsFromMetrics() {
            let metrics = NetworkTimingMetrics(
                phases: [
                    .init(kind: .dns, start: 0, duration: 0.01),
                    .init(kind: .request, start: 0.02, duration: 0.005),
                    .init(kind: .timeToFirstByte, start: 0.025, duration: 0.1),
                    .init(kind: .response, start: 0.125, duration: 0.02)
                ],
                protocolName: "h2", isReusedConnection: false, isCacheHit: false
            )
            var entry = NetworkEntry(
                timestamp: Date(timeIntervalSince1970: 0), method: "GET", url: "https://example.com/",
                host: "example.com", path: "/", requestHeaders: [:], requestBody: nil, isComplete: true
            )
            entry.metrics = metrics

            let actual = HTTPArchive([entry], redaction: .none).log.entries[0]

            #expect(actual.request.httpVersion == "HTTP/2")
            #expect(abs(actual.timings.dns - 10) < 0.001)
            #expect(actual.timings.connect == -1)
            #expect(actual.timings.ssl == -1)
            #expect(abs(actual.timings.send - 5) < 0.001)
            #expect(abs(actual.timings.wait - 100) < 0.001)
            #expect(abs(actual.timings.receive - 20) < 0.001)
        }

        @Test("A binary response body goes in base64")
        func binaryBody() {
            var entry = NetworkEntry(
                timestamp: Date(timeIntervalSince1970: 0), method: "GET", url: "https://example.com/logo",
                host: "example.com", path: "/logo", requestHeaders: [:], requestBody: nil, isComplete: true
            )
            entry.responseBody = Data([0xFF, 0xD8, 0xFF])

            let actual = HTTPArchive([entry], redaction: .none).log.entries[0].response.content

            #expect(actual.encoding == "base64")
            #expect(actual.text == "/9j/")
        }

        @Test("No requests add nothing to the report")
        func noRequests() {
            var actual = DebugDrawerReport()

            NetworkPlugin.contribute([], to: &actual, redaction: .standard)

            #expect(actual.files.isEmpty)
        }
    }
#endif
