#if DEBUG
    import DebugDrawer
    @testable import DebugDrawerNetworkPlugin
    import Foundation
    import Testing

    @Suite
    struct NetworkArchiveExportTests {
        @Test("The exported file is HAR 1.2 with a creator, and one entry per request with its request, response, start and time")
        func specShape() throws {
            let start = Date(timeIntervalSince1970: 1_800_000_000)
            let entries = [
                NetworkEntry(
                    timestamp: start + 1, method: "POST", url: "https://api.example.com/v1/orders", host: "api.example.com",
                    path: "/v1/orders", requestHeaders: ["Content-Type": "application/json"], requestBody: Data(#"{"item":"tea"}"#.utf8),
                    statusCode: 201, responseHeaders: ["Content-Type": "application/json"], responseBody: Data(#"{"id":7}"#.utf8),
                    duration: 0.25, isComplete: true
                ),
                NetworkEntry(
                    timestamp: start, method: "GET", url: "https://api.example.com/v1/greeting", host: "api.example.com",
                    path: "/v1/greeting", requestHeaders: [:], requestBody: nil, statusCode: 200, duration: 0.1, isComplete: true
                )
            ]
            let sut = NetworkArchiveFile(entries: entries, redaction: .standard)
            let expectedEntryKeys: Set = ["startedDateTime", "time", "request", "response", "cache", "timings"]
            let expectedRequestKeys: Set = ["method", "url", "httpVersion", "cookies", "headers", "queryString", "headersSize", "bodySize"]
            let expectedResponseKeys: Set = [
                "status", "statusText", "httpVersion", "cookies", "headers", "content", "redirectURL", "headersSize", "bodySize"
            ]

            let actual = sut.data

            let har = try #require(try JSONSerialization.jsonObject(with: actual) as? [String: Any])
            let log = try #require(har["log"] as? [String: Any])
            let creator = try #require(log["creator"] as? [String: String])
            let archived = try #require(log["entries"] as? [[String: Any]])
            #expect(log["version"] as? String == "1.2")
            #expect(creator["name"] == "DebugDrawer")
            #expect(creator["version"]?.isEmpty == false)
            #expect(archived.count == 2)
            for entry in archived {
                let request = try #require(entry["request"] as? [String: Any])
                let response = try #require(entry["response"] as? [String: Any])
                #expect(expectedEntryKeys.isSubset(of: entry.keys))
                #expect(expectedRequestKeys.isSubset(of: request.keys))
                #expect(expectedResponseKeys.isSubset(of: response.keys))
                #expect(entry["time"] is Double)
            }
            #expect(archived.map { $0["startedDateTime"] as? String } == ["2027-01-15T08:00:00.000Z", "2027-01-15T08:00:01.000Z"])
            #expect(archived.map { $0["time"] as? Double } == [100, 250])
        }

        @Test("The file is named after the newest request's time, with a .har extension")
        func fileName() {
            let entries = [0.0, 60].map { offset in
                NetworkEntry(
                    timestamp: Date(timeIntervalSince1970: 1_800_000_000 + offset), method: "GET", url: "https://example.com/",
                    host: "example.com", path: "/", requestHeaders: [:], requestBody: nil, isComplete: true
                )
            }
            let expected = "Network 2027-01-15T08-01-00Z.har"

            let actual = NetworkArchiveFile(entries: entries, redaction: .none).fileName

            #expect(actual == expected)
        }

        @Test("With a filter applied, the export holds only the requests the list shows")
        func filteredExport() throws {
            let entries = [(200, "/v1/a"), (500, "/v1/b"), (404, "/v1/c"), (503, "/v2/d")].map { status, path in
                NetworkEntry(
                    timestamp: Date(timeIntervalSince1970: 0), method: "GET", url: "https://api.example.com\(path)",
                    host: "api.example.com", path: path, requestHeaders: [:], requestBody: nil, statusCode: status, isComplete: true
                )
            }
            let shown = NetworkStore.entries(entries, matching: .serverError, text: "/v1/")
            let sut = NetworkArchiveFile(entries: shown, redaction: .none)
            let expected = ["https://api.example.com/v1/b"]

            let actual = try JSONDecoder().decode(HTTPArchive.self, from: sut.data).log.entries.map(\.request.url)

            #expect(actual == expected)
        }

        @Test("A header a redaction rule matches is masked in the exported file; other headers are kept")
        func headerRedacted() throws {
            let entry = NetworkEntry(
                timestamp: Date(timeIntervalSince1970: 0), method: "GET", url: "https://api.example.com/v1/me", host: "api.example.com",
                path: "/v1/me", requestHeaders: ["Authorization": "Bearer s3cr3t", "X-Api-Signature": "sig-42", "Accept": "application/json"],
                requestBody: nil, statusCode: 200, responseHeaders: ["X-Api-Signature": "sig-43"], isComplete: true
            )
            let redaction = DebugDrawerRedaction.standard.adding(headers: ["X-Api-Signature"])
            let sut = NetworkArchiveFile(entries: [entry], redaction: redaction)
            let expectedRequest = [
                HTTPArchive.NameValue(name: "Accept", value: "application/json"),
                HTTPArchive.NameValue(name: "Authorization", value: "[REDACTED]"),
                HTTPArchive.NameValue(name: "X-Api-Signature", value: "[REDACTED]")
            ]
            let expectedResponse = [HTTPArchive.NameValue(name: "X-Api-Signature", value: "[REDACTED]")]

            let data = sut.data

            let text = try #require(String(bytes: data, encoding: .utf8))
            let actual = try JSONDecoder().decode(HTTPArchive.self, from: data).log.entries[0]
            #expect(actual.request.headers == expectedRequest)
            #expect(actual.response.headers == expectedResponse)
            #expect(!text.contains("s3cr3t"))
            #expect(!text.contains("sig-4"))
        }

        @Test("Query items, cookies and JSON body values the rules call sensitive are masked; the rest are kept")
        func queryCookiesAndBodyRedacted() throws {
            let entry = NetworkEntry(
                timestamp: Date(timeIntervalSince1970: 0), method: "POST", url: "https://api.example.com/login?api_key=k3y&lang=en",
                host: "api.example.com", path: "/login", requestHeaders: ["Cookie": "theme=dark; sessionid=abc123"],
                requestBody: Data(#"{"user":"ada","password":"hunter2"}"#.utf8), statusCode: 200,
                responseHeaders: ["Set-Cookie": "sessionid=def456; Path=/; HttpOnly; Secure"],
                responseBody: Data(#"{"token":"t0k3n","name":"Ada"}"#.utf8), isComplete: true
            )
            // Not the standard rules, which mask the Cookie headers whole: these mask by name only.
            let redaction = DebugDrawerRedaction(keys: ["session", "key", "password", "token"])
            let sut = NetworkArchiveFile(entries: [entry], redaction: redaction)
            let expectedQuery = [
                HTTPArchive.NameValue(name: "api_key", value: "[REDACTED]"),
                HTTPArchive.NameValue(name: "lang", value: "en")
            ]
            let expectedRequestCookies = [
                HTTPArchive.Cookie(name: "theme", value: "dark"),
                HTTPArchive.Cookie(name: "sessionid", value: "[REDACTED]")
            ]
            let expectedResponseCookies = [
                HTTPArchive.Cookie(
                    name: "sessionid", value: "[REDACTED]", path: "/", domain: "api.example.com", httpOnly: true, secure: true
                )
            ]
            let expectedPostData = #"{"password":"[REDACTED]","user":"ada"}"#
            let expectedContent = #"{"name":"Ada","token":"[REDACTED]"}"#

            let data = sut.data

            let text = try #require(String(bytes: data, encoding: .utf8))
            let actual = try JSONDecoder().decode(HTTPArchive.self, from: data).log.entries[0]
            #expect(actual.request.queryString == expectedQuery)
            #expect(actual.request.cookies == expectedRequestCookies)
            #expect(actual.response.cookies == expectedResponseCookies)
            #expect(actual.request.postData?.text == expectedPostData)
            #expect(actual.response.content.text == expectedContent)
            for secret in ["k3y", "abc123", "def456", "hunter2", "t0k3n"] {
                #expect(!text.contains(secret))
            }
        }

        @Test("The standard rules mask every cookie's value, since they mask the Cookie and Set-Cookie headers")
        func standardMasksCookies() {
            let entry = NetworkEntry(
                timestamp: Date(timeIntervalSince1970: 0), method: "GET", url: "https://example.com/", host: "example.com",
                path: "/", requestHeaders: ["Cookie": "theme=dark"], requestBody: nil, statusCode: 200,
                responseHeaders: ["Set-Cookie": "theme=light"], isComplete: true
            )
            let expected = ["[REDACTED]", "[REDACTED]"]

            let archived = HTTPArchive([entry], redaction: .standard).log.entries[0]

            let actual = (archived.request.cookies + archived.response.cookies).map(\.value)
            #expect(actual == expected)
        }

        @Test("A binary request body goes in base64, marked with the custom _encoding field")
        func binaryRequestBody() throws {
            let entry = NetworkEntry(
                timestamp: Date(timeIntervalSince1970: 0), method: "PUT", url: "https://example.com/avatar", host: "example.com",
                path: "/avatar", requestHeaders: ["Content-Type": "image/jpeg"], requestBody: Data([0xFF, 0xD8, 0xFF]), isComplete: false
            )

            let data = NetworkArchiveFile(entries: [entry], redaction: .none).data

            let har = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            let log = try #require(har["log"] as? [String: Any])
            let entries = try #require(log["entries"] as? [[String: Any]])
            let request = try #require(entries.first?["request"] as? [String: Any])
            let actual = try #require(request["postData"] as? [String: String])
            #expect(actual == ["mimeType": "image/jpeg", "text": "/9j/", "_encoding": "base64"])
        }

        @Test("A request still waiting has no response size: the response's body size is -1, as the format asks for unknown")
        func unknownSizes() {
            let entry = NetworkEntry(
                timestamp: Date(timeIntervalSince1970: 0), method: "GET", url: "https://example.com/", host: "example.com",
                path: "/", requestHeaders: [:], requestBody: nil, isComplete: false
            )

            let actual = HTTPArchive([entry], redaction: .none).log.entries[0]

            #expect(actual.response.bodySize == -1)
            #expect(actual.response.headersSize == -1)
            #expect(actual.request.headersSize == -1)
        }
    }
#endif
