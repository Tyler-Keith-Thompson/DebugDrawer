#if DEBUG
    @testable import DebugDrawerNetworkPlugin
    import Foundation
    import Testing

    @Suite
    struct NetworkReplayDraftTests {
        @Test("A draft of a captured request describes it exactly: method, URL, headers and body")
        func prefill() throws {
            let entry = NetworkEntry(
                timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000), method: "POST",
                url: "https://api.example.com/v1/orders?draft=1", host: "api.example.com", path: "/v1/orders",
                requestHeaders: ["Content-Type": "application/json", "Authorization": "Bearer abc"],
                requestBody: Data(#"{"item":"tea"}"#.utf8), isComplete: true
            )
            let expectedHeaders = ["Authorization": "Bearer abc", "Content-Type": "application/json"]

            let sut = NetworkReplayDraft(entry)
            let actual = try #require(sut.request)

            #expect(sut.original == entry.id)
            #expect(sut.method == "POST")
            #expect(sut.url == "https://api.example.com/v1/orders?draft=1")
            #expect(sut.headers.map(\.name) == ["Authorization", "Content-Type"])
            #expect(sut.body == .text(#"{"item":"tea"}"#))
            #expect(actual.httpMethod == "POST")
            #expect(actual.url?.absoluteString == "https://api.example.com/v1/orders?draft=1")
            #expect(actual.allHTTPHeaderFields == expectedHeaders)
            #expect(actual.httpBody == Data(#"{"item":"tea"}"#.utf8))
        }

        @Test("Content-Length is left out of the headers, since the URL loading system sets it from the body sent")
        func dropsContentLength() {
            let entry = NetworkEntry(
                timestamp: Date(), method: "PUT", url: "https://example.com/a", host: "example.com", path: "/a",
                requestHeaders: ["content-length": "4", "Accept": "*/*"], requestBody: Data("abcd".utf8), isComplete: true
            )

            let actual = NetworkReplayDraft(entry).headers.map(\.name)

            #expect(actual == ["Accept"])
        }

        @Test("A body that isn't UTF-8 is kept as captured and sent byte for byte")
        func binaryBody() throws {
            let bytes = Data([0xFF, 0xFE, 0x00, 0x81])
            let entry = NetworkEntry(
                timestamp: Date(), method: "POST", url: "https://example.com/upload", host: "example.com", path: "/upload",
                requestHeaders: [:], requestBody: bytes, isComplete: true
            )

            let sut = NetworkReplayDraft(entry)
            let actual = try #require(sut.request)

            #expect(sut.body == .binary(bytes))
            #expect(actual.httpBody == bytes)
        }

        @Test("A request with no body sends none, and neither does an emptied text body")
        func noBody() throws {
            let entry = NetworkEntry(
                timestamp: Date(), method: "DELETE", url: "https://example.com/a/1", host: "example.com", path: "/a/1",
                requestHeaders: [:], requestBody: nil, isComplete: true
            )
            var sut = NetworkReplayDraft(entry)
            let before = try #require(sut.request).httpBody
            sut.body = .text("")

            let actual = try #require(sut.request).httpBody

            #expect(before == nil)
            #expect(actual == nil)
        }

        @Test("An edited method, URL, header and body make the request sent")
        func edited() throws {
            let entry = NetworkEntry(
                timestamp: Date(), method: "GET", url: "https://api.example.com/v1/users/1", host: "api.example.com", path: "/v1/users/1",
                requestHeaders: ["Accept": "application/json"], requestBody: nil, isComplete: true
            )
            var sut = NetworkReplayDraft(entry)
            sut.method = "PATCH"
            sut.url = "https://staging.example.com/v1/users/2"
            sut.headers[0].value = "text/plain"
            sut.headers.append(NetworkNameValue(name: "X-Trace", value: "replay-test"))
            sut.body = .text("name=Ada")
            let expectedHeaders = ["Accept": "text/plain", "X-Trace": "replay-test"]

            let actual = try #require(sut.request)

            #expect(actual.httpMethod == "PATCH")
            #expect(actual.url?.absoluteString == "https://staging.example.com/v1/users/2")
            #expect(actual.allHTTPHeaderFields == expectedHeaders)
            #expect(actual.httpBody == Data("name=Ada".utf8))
        }

        @Test("A URL that isn't http or https with a host can't be sent, and says so", arguments: [
            ("https://api.example.com/v1", true),
            ("http://127.0.0.1:8080/", true),
            ("  https://example.com  ", true),
            ("", false),
            ("example.com/v1", false),
            ("ftp://example.com/file", false),
            ("https://", false),
            ("file:///tmp/a", false)
        ])
        func urlValidation(url: String, isValid: Bool) {
            var sut = NetworkReplayDraft(NetworkEntry(
                timestamp: Date(), method: "GET", url: "https://example.com/", host: "example.com", path: "/",
                requestHeaders: [:], requestBody: nil, isComplete: true
            ))
            sut.url = url
            let expectedProblem: String? = isValid ? nil : "Enter an http or https URL with a host."

            let actual = sut.urlProblem

            #expect(actual == expectedProblem)
            #expect((sut.request != nil) == isValid)
        }

        @Test("A GET or HEAD with a body can't be sent, since the URL loading system refuses one; another method can")
        func bodyOnGet() {
            var sut = NetworkReplayDraft(NetworkEntry(
                timestamp: Date(), method: "POST", url: "https://example.com/a", host: "example.com", path: "/a",
                requestHeaders: [:], requestBody: Data("x=1".utf8), isComplete: true
            ))
            let methods = ["GET", "HEAD", "get", "POST", "PUT", "OPTIONS"]
            let expected = [true, true, true, false, false, false]

            let actual = methods.map { method in
                sut.method = method
                return sut.bodyProblem != nil && sut.request == nil
            }

            #expect(actual == expected)
            sut.method = "GET"
            #expect(sut.bodyProblem == "A GET can't carry a body. Remove it, or choose another method.")
        }

        @Test("POST, PUT, PATCH, DELETE and other unsafe methods ask before sending; GET, HEAD, OPTIONS and TRACE don't")
        func confirmation() {
            var sut = NetworkReplayDraft(NetworkEntry(
                timestamp: Date(), method: "GET", url: "https://example.com/", host: "example.com", path: "/",
                requestHeaders: [:], requestBody: nil, isComplete: true
            ))
            let methods = ["GET", "HEAD", "OPTIONS", "TRACE", "get", "POST", "PUT", "PATCH", "DELETE", "PURGE"]
            let expected = [false, false, false, false, false, true, true, true, true, true]

            let actual = methods.map { method in
                sut.method = method
                return sut.needsConfirmation
            }

            #expect(actual == expected)
        }

        @Test("The methods offered are the standard ones, and the request's own when it is another")
        func methods() {
            var sut = NetworkReplayDraft(NetworkEntry(
                timestamp: Date(), method: "GET", url: "https://example.com/", host: "example.com", path: "/",
                requestHeaders: [:], requestBody: nil, isComplete: true
            ))
            let standard = ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"]

            let actualStandard = sut.methods
            sut.method = "PURGE"
            let actualCustom = sut.methods

            #expect(actualStandard == standard)
            #expect(actualCustom == standard + ["PURGE"])
        }

        @Test("A body the log cut short is held as cut, with its full size, and nothing is sent until it is edited or removed")
        func truncatedBody() throws {
            let kept = Data(#"{"items":["tea","#.utf8)
            let entry = NetworkEntry(
                timestamp: Date(), method: "POST", url: "https://api.example.com/v1/orders", host: "api.example.com", path: "/v1/orders",
                requestHeaders: [:], requestBody: kept, requestBodySize: 4096, isComplete: true
            )
            let expectedProblem = "Only part of the body was kept, so it can't be sent. Edit the kept part, or remove the body."

            var sut = NetworkReplayDraft(entry)
            let body = sut.body
            let problem = sut.bodyProblem
            let request = sut.request
            sut.body = .text(#"{"items":["tea","coffee"]}"#)
            let replaced = try #require(sut.request)
            sut.body = .text("")
            let removed = try #require(sut.request)

            #expect(body == .truncated(kept: kept, size: 4096))
            #expect(problem == expectedProblem)
            #expect(request == nil)
            #expect(replaced.httpBody == Data(#"{"items":["tea","coffee"]}"#.utf8))
            #expect(removed.httpBody == nil)
        }

        @Test("A cut body stays unsendable whatever the method: a GET is told the body was cut, not that it can't carry one")
        func truncatedBodyAnyMethod() {
            var sut = NetworkReplayDraft(NetworkEntry(
                timestamp: Date(), method: "PUT", url: "https://example.com/a", host: "example.com", path: "/a",
                requestHeaders: [:], requestBody: Data([0xFF, 0xFE]), requestBodySize: 10, isComplete: true
            ))
            let methods = ["PUT", "POST", "GET"]

            let actual = methods.map { method in
                sut.method = method
                return sut.request == nil && sut.bodyProblem?.hasPrefix("Only part of the body was kept") == true
            }

            #expect(actual == [true, true, true])
        }

        @Test("A body the log kept whole is no different from one with no size: it is sent as captured")
        func wholeBodyWithSize() throws {
            let body = Data("name=Ada".utf8)
            let entry = NetworkEntry(
                timestamp: Date(), method: "POST", url: "https://example.com/a", host: "example.com", path: "/a",
                requestHeaders: [:], requestBody: body, requestBodySize: body.count, isComplete: true
            )

            let sut = NetworkReplayDraft(entry)
            let actual = try #require(sut.request)

            #expect(sut.body == .text("name=Ada"))
            #expect(actual.httpBody == body)
        }
    }
#endif
