#if DEBUG
    import DebugDrawer
    @testable import DebugDrawerNetworkPlugin
    import Foundation
    import Testing

    @Suite
    struct NetworkArchiveImportTests {
        @Test("Exporting then importing gives back each request's method, URL, status, headers and bodies")
        func roundTrip() throws {
            let start = Date(timeIntervalSince1970: 1_800_000_000)
            let entries = [
                NetworkEntry(
                    timestamp: start + 1, method: "POST", url: "https://api.example.com/v1/orders?page=2", host: "api.example.com",
                    path: "/v1/orders", requestHeaders: ["Content-Type": "application/json", "X-Client": "app"],
                    requestBody: Data(#"{"item":"tea"}"#.utf8), statusCode: 201,
                    responseHeaders: ["Content-Type": "application/json", "Location": "/v1/orders/7"],
                    responseBody: Data(#"{"id":7}"#.utf8), duration: 0.25, isComplete: true
                ),
                NetworkEntry(
                    timestamp: start, method: "GET", url: "https://api.example.com/v1/missing", host: "api.example.com",
                    path: "/v1/missing", requestHeaders: ["Accept": "text/plain"], requestBody: nil, statusCode: 404,
                    responseHeaders: ["Content-Type": "text/plain"], responseBody: Data("Not here".utf8), duration: 0.1, isComplete: true
                )
            ]
            let data = NetworkArchiveFile(entries: entries, redaction: .none).data

            let actual = try NetworkImportedLog(fileName: "session.har", data: data).entries

            try #require(actual.count == 2)
            for (expected, imported) in zip(entries, actual) {
                #expect(imported.method == expected.method)
                #expect(imported.url == expected.url)
                #expect(imported.host == expected.host)
                #expect(imported.path == expected.path)
                #expect(imported.statusCode == expected.statusCode)
                #expect(imported.requestHeaders == expected.requestHeaders)
                #expect(imported.responseHeaders == expected.responseHeaders)
                #expect(imported.requestBody == expected.requestBody)
                #expect(imported.responseBody == expected.responseBody)
                #expect(abs(imported.timestamp.timeIntervalSince(expected.timestamp)) < 0.001)
                #expect(imported.duration.map { ($0 * 1000).rounded() } == expected.duration.map { ($0 * 1000).rounded() })
                #expect(imported.isComplete)
            }
        }

        @Test("Binary request and response bodies come back byte for byte through base64")
        func binaryRoundTrip() throws {
            let bytes = Data((0 ... 255).map(UInt8.init))
            let entry = NetworkEntry(
                timestamp: Date(timeIntervalSince1970: 0), method: "PUT", url: "https://example.com/blob", host: "example.com",
                path: "/blob", requestHeaders: ["Content-Type": "application/octet-stream"], requestBody: bytes, statusCode: 200,
                responseHeaders: ["Content-Type": "image/png"], responseBody: Data([0x89, 0x50, 0x4E, 0x47, 0xFF]), isComplete: true
            )
            let data = NetworkArchiveFile(entries: [entry], redaction: .standard).data

            let actual = try #require(try NetworkImportedLog(fileName: "blob.har", data: data).entries.first)

            #expect(actual.requestBody == bytes)
            #expect(actual.responseBody == Data([0x89, 0x50, 0x4E, 0x47, 0xFF]))
        }

        @Test("A request that got no answer comes back with its error and no status")
        func failedRoundTrip() throws {
            let entry = NetworkEntry(
                timestamp: Date(timeIntervalSince1970: 0), method: "GET", url: "https://api.example.com/v1/greeting",
                host: "api.example.com", path: "/v1/greeting", requestHeaders: [:], requestBody: nil, duration: 0.01,
                error: "The Internet connection appears to be offline.", isComplete: true
            )
            let data = NetworkArchiveFile(entries: [entry], redaction: .none).data

            let actual = try #require(try NetworkImportedLog(fileName: "offline.har", data: data).entries.first)

            #expect(actual.statusCode == nil)
            #expect(actual.responseHeaders == nil)
            #expect(actual.error == "The Internet connection appears to be offline.")
            #expect(actual.isFailure)
        }

        @Test("An archive shaped like Chrome DevTools' reads: pages, custom fields, HTTP/2 pseudo-headers, null cookie expiry and a response error")
        func chromeShaped() throws {
            let har = """
            {"log": {"version": "1.2", "creator": {"name": "WebInspector", "version": "537.36"},
              "pages": [{"startedDateTime": "2026-03-02T09:15:00.000Z", "id": "page_1", "title": "https://shop.example.com/",
                         "pageTimings": {"onContentLoad": 310.2, "onLoad": 512.9}}],
              "entries": [
                {"_initiator": {"type": "script"}, "_priority": "High", "_resourceType": "fetch", "cache": {},
                 "connection": "443", "pageref": "page_1",
                 "request": {"method": "GET", "url": "https://shop.example.com/api/cart?id=12", "httpVersion": "http/2.0",
                   "headers": [{"name": ":authority", "value": "shop.example.com"}, {"name": ":method", "value": "GET"},
                               {"name": "accept", "value": "application/json"}],
                   "queryString": [{"name": "id", "value": "12"}],
                   "cookies": [{"name": "theme", "value": "dark", "path": "/", "domain": "shop.example.com",
                                "expires": null, "httpOnly": false, "secure": true}],
                   "headersSize": -1, "bodySize": 0},
                 "response": {"status": 200, "statusText": "", "httpVersion": "http/2.0",
                   "headers": [{"name": "content-type", "value": "application/json"}, {"name": "vary", "value": "Accept"},
                               {"name": "vary", "value": "Origin"}],
                   "cookies": [], "content": {"size": 11, "mimeType": "application/json", "compression": 0, "text": "{\\"items\\":2}"},
                   "redirectURL": "", "headersSize": -1, "bodySize": -1, "_transferSize": 120, "_error": null},
                 "serverIPAddress": "203.0.113.7", "startedDateTime": "2026-03-02T09:15:00.120Z", "time": 48.31,
                 "timings": {"blocked": 1.2, "dns": -1, "ssl": -1, "connect": -1, "send": 0.1, "wait": 45.0, "receive": 2.0,
                             "_blocked_queueing": 0.8}},
                {"_resourceType": "fetch", "cache": {}, "pageref": "page_1",
                 "request": {"method": "POST", "url": "https://shop.example.com/api/checkout", "httpVersion": "",
                   "headers": [{"name": "content-type", "value": "application/x-www-form-urlencoded"}],
                   "queryString": [], "cookies": [], "headersSize": -1, "bodySize": 13,
                   "postData": {"mimeType": "application/x-www-form-urlencoded", "text": "card=4111&x=1",
                                "params": [{"name": "card", "value": "4111"}, {"name": "x", "value": "1"}]}},
                 "response": {"status": 0, "statusText": "", "httpVersion": "", "headers": [], "cookies": [],
                   "content": {"size": 0, "mimeType": "x-unknown"}, "redirectURL": "", "headersSize": -1, "bodySize": -1,
                   "_transferSize": 0, "_error": "net::ERR_CONNECTION_REFUSED"},
                 "startedDateTime": "2026-03-02T09:15:01.500Z", "time": 3.5, "timings": {"blocked": 3.5, "send": 0, "wait": 0, "receive": 0}}
              ]}}
            """
            let expectedCartHeaders = ["accept": "application/json"]
            let expectedCartResponseHeaders = ["content-type": "application/json", "vary": "Accept, Origin"]

            let actual = try NetworkImportedLog(fileName: "shop.example.com.har", data: Data(har.utf8)).entries

            try #require(actual.count == 2)
            let checkout = actual[0]
            let cart = actual[1]
            #expect(cart.method == "GET")
            #expect(cart.url == "https://shop.example.com/api/cart?id=12")
            #expect(cart.host == "shop.example.com")
            #expect(cart.path == "/api/cart")
            #expect(cart.requestHeaders == expectedCartHeaders)
            #expect(cart.statusCode == 200)
            #expect(cart.responseHeaders == expectedCartResponseHeaders)
            #expect(cart.responseBody == Data(#"{"items":2}"#.utf8))
            #expect(cart.error == nil)
            #expect(abs(cart.timestamp.timeIntervalSince1970 - 1_772_442_900.12) < 0.001)
            #expect(cart.duration.map { ($0 * 100_000).rounded() } == 4831)
            #expect(checkout.method == "POST")
            #expect(checkout.requestBody == Data("card=4111&x=1".utf8))
            #expect(checkout.statusCode == nil)
            #expect(checkout.error == "net::ERR_CONNECTION_REFUSED")
            #expect(checkout.isFailure)
        }

        @Test("An archive shaped like Charles' reads: an offset start, whole-number times, missing cookies and timings, base64 content and a comment")
        func charlesShaped() throws {
            let har = """
            {
              "log": {
                "version": "1.2",
                "creator": {"name": "Charles Proxy", "version": "5.0", "comment": ""},
                "entries": [
                  {
                    "startedDateTime": "2026-04-10T14:03:05+02:00",
                    "time": 120,
                    "request": {
                      "method": "GET",
                      "url": "https://cdn.example.com/img/logo.png",
                      "httpVersion": "HTTP/1.1",
                      "headers": [{"name": "Host", "value": "cdn.example.com"}, {"name": "Accept", "value": "image/*"}],
                      "queryString": [],
                      "headersSize": 64,
                      "bodySize": 0,
                      "comment": ""
                    },
                    "response": {
                      "_charlesStatus": "COMPLETE",
                      "status": 200,
                      "statusText": "OK",
                      "httpVersion": "HTTP/1.1",
                      "headers": [{"name": "Content-Type", "value": "image/png"}],
                      "content": {"size": 4, "mimeType": "image/png", "text": "iVBORw==", "encoding": "base64"},
                      "redirectURL": null,
                      "headersSize": 80,
                      "bodySize": 4
                    },
                    "serverIPAddress": "198.51.100.4",
                    "cache": {},
                    "comment": "Recorded through the proxy"
                  }
                ]
              }
            }
            """

            let actual = try #require(try NetworkImportedLog(fileName: "charles.har", data: Data(har.utf8)).entries.first)

            #expect(actual.method == "GET")
            #expect(actual.url == "https://cdn.example.com/img/logo.png")
            #expect(actual.statusCode == 200)
            #expect(actual.requestHeaders == ["Host": "cdn.example.com", "Accept": "image/*"])
            #expect(actual.responseBody == Data([0x89, 0x50, 0x4E, 0x47]))
            #expect(actual.timestamp == Date(timeIntervalSince1970: 1_775_822_585))
            #expect(actual.duration == 0.12)
        }

        @Test("HAR 1.1, or an archive with no version, reads as 1.2 does")
        func olderVersions() throws {
            let versions = [#""version": "1.1","#, ""]
            for version in versions {
                let har = """
                {"log": {\(version) "entries": [{"request": {"method": "GET", "url": "https://example.com/"}, "response": {"status": 204}}]}}
                """

                let actual = try NetworkImportedLog(fileName: "old.har", data: Data(har.utf8)).entries

                #expect(actual.map(\.statusCode) == [204])
            }
        }

        @Test("Requests are listed newest first, as the log lists captured ones")
        func newestFirst() throws {
            let har = """
            {"log": {"version": "1.2", "entries": [
              {"startedDateTime": "2026-01-01T00:00:00.000Z", "request": {"method": "GET", "url": "https://example.com/a"}},
              {"startedDateTime": "2026-01-01T00:00:05.000Z", "request": {"method": "GET", "url": "https://example.com/b"}}
            ]}}
            """
            let expected = ["https://example.com/b", "https://example.com/a"]

            let actual = try NetworkImportedLog(fileName: "two.har", data: Data(har.utf8)).entries.map(\.url)

            #expect(actual == expected)
        }

        @Test("A file that isn't JSON is refused as not JSON")
        func notJSON() {
            let data = Data("<html>Not a HAR</html>".utf8)

            #expect(throws: HTTPArchive.ReadError.notJSON) {
                try NetworkImportedLog(fileName: "page.html", data: data)
            }
        }

        @Test("JSON with no log of entries is refused as not an archive", arguments: [
            #"{"name": "package", "version": "1.2"}"#,
            #"{"log": {"version": "1.2"}}"#,
            #"{"log": {"version": "1.2", "entries": {}}}"#,
            "[]"
        ])
        func notAnArchive(json: String) {
            let data = Data(json.utf8)

            #expect(throws: HTTPArchive.ReadError.notAnArchive) {
                try NetworkImportedLog(fileName: "other.json", data: data)
            }
        }

        @Test("An archive of another major version is refused, naming the version")
        func unsupportedVersion() {
            let data = Data(#"{"log": {"version": "2.0", "entries": []}}"#.utf8)

            #expect(throws: HTTPArchive.ReadError.unsupportedVersion("2.0")) {
                try NetworkImportedLog(fileName: "future.har", data: data)
            }
        }

        @Test("An entry with no URL is refused, naming its position")
        func invalidEntry() {
            let data = Data("""
            {"log": {"version": "1.2", "entries": [
              {"request": {"method": "GET", "url": "https://example.com/"}},
              {"request": {"method": "GET"}}
            ]}}
            """.utf8)

            #expect(throws: HTTPArchive.ReadError.invalidEntry(1)) {
                try NetworkImportedLog(fileName: "broken.har", data: data)
            }
        }

        @Test("A file that can't be opened is refused as unreadable")
        func unreadableFile() {
            let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString)/missing.har")

            #expect(throws: HTTPArchive.ReadError.unreadableFile) {
                try NetworkImportedLog(contentsOf: url)
            }
        }

        @Test("A file opened from disk takes its name from the file")
        func fileName() throws {
            let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appending(path: "session.har")
            try Data(#"{"log": {"version": "1.2", "entries": []}}"#.utf8).write(to: url)
            defer { try? FileManager.default.removeItem(at: folder) }

            let actual = try NetworkImportedLog(contentsOf: url)

            #expect(actual.fileName == "session.har")
            #expect(actual.entries.isEmpty)
        }

        @Test("The message for a refused file names it and says what is wrong")
        func issueMessage() {
            let sut = NetworkImportIssue(fileName: "future.har", error: .unsupportedVersion("2.0"))
            let expected = "“future.har” wasn't imported. The archive is HAR 2.0; only HAR 1.1 and 1.2 can be read."

            let actual = sut.message

            #expect(actual == expected)
        }
    }
#endif
