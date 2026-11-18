#if DEBUG
    @testable import DebugDrawerNetworkPlugin
    import Foundation
    import Testing

    @Suite
    struct NetworkBodyCaptureTests {
        @Test("A body under the limit is kept whole, and not marked truncated")
        func keepsSmallBody() {
            var sut = NetworkBodyCapture(limit: 16)
            let expected = Data(#"{"ok":true}"#.utf8)

            sut.append(expected)

            let actual = sut.body
            #expect(actual.data == expected)
            #expect(actual.size == expected.count)
        }

        @Test("A body of exactly the limit is kept whole")
        func keepsBodyAtLimit() {
            var sut = NetworkBodyCapture(limit: 4)
            let expected = Data("abcd".utf8)

            sut.append(expected)

            let actual = sut.body
            #expect(actual.data == expected)
            #expect(actual.size == 4)
        }

        @Test("A body one byte over the limit keeps the first limit bytes and counts every byte")
        func cutsBodyOverLimit() {
            var sut = NetworkBodyCapture(limit: 4)
            let expectedData = Data("abcd".utf8)
            let expectedSize = 5

            sut.append(Data("abcde".utf8))

            let actual = sut.body
            #expect(actual.data == expectedData)
            #expect(actual.size == expectedSize)
        }

        @Test("Chunks that cross the limit keep the bytes before it, and later chunks are only counted")
        func cutsAcrossChunks() {
            var sut = NetworkBodyCapture(limit: 5)
            let expectedData = Data("abcde".utf8)
            let expectedSize = 9

            sut.append(Data("abc".utf8))
            sut.append(Data("def".utf8))
            sut.append(Data("ghi".utf8))

            let actual = sut.body
            #expect(actual.data == expectedData)
            #expect(actual.size == expectedSize)
        }

        @Test("A limit of zero keeps no bytes and counts them all")
        func zeroLimitKeepsNothing() {
            var sut = NetworkBodyCapture(limit: 0)
            let expectedSize = 3

            sut.append(Data("abc".utf8))

            let actual = sut.body
            #expect(actual.data.isEmpty)
            #expect(actual.size == expectedSize)
        }

        @Test("An empty body is kept empty, and not marked truncated")
        func emptyBody() {
            let sut = NetworkBodyCapture(limit: 4)

            let actual = sut.body

            #expect(actual.data.isEmpty)
            #expect(actual.size == 0)
        }

        @Test("A cut that splits a UTF-8 character drops its leading bytes, so the kept text still reads as UTF-8")
        func dropsSplitCharacter() throws {
            // "é" is two bytes (C3 A9); a limit of 3 keeps "ab" and the first byte of "é".
            var sut = NetworkBodyCapture(limit: 3)
            let expected = "ab"

            sut.append(Data("abé!".utf8))

            let actual = try #require(String(data: sut.body.data, encoding: .utf8))
            #expect(actual == expected)
            #expect(sut.body.size == 5)
        }

        @Test("A cut after a whole multi-byte character keeps it")
        func keepsWholeCharacter() throws {
            // "€" is three bytes; a limit of 4 keeps "a€".
            var sut = NetworkBodyCapture(limit: 4)
            let expected = "a€"

            sut.append(Data("a€b".utf8))

            let actual = try #require(String(data: sut.body.data, encoding: .utf8))
            #expect(actual == expected)
        }

        @Test("A truncated entry keeps the bytes it was given, reports the full size, and labels its size by it")
        func truncatedEntry() {
            let sut = NetworkEntry(
                timestamp: Date(timeIntervalSinceReferenceDate: 0), method: "GET", url: "https://api.example.com/v1/file",
                host: "api.example.com", path: "/v1/file", requestHeaders: [:], requestBody: nil, statusCode: 200,
                responseBody: Data(repeating: UInt8(ascii: "a"), count: 1024), responseBodySize: 3 * 1024 * 1024, isComplete: true
            )
            let expectedSize = 3 * 1024 * 1024
            let expectedLabel = "3.0 MB"

            let actual = sut.responseBodySize

            #expect(actual == expectedSize)
            #expect(sut.isResponseBodyTruncated)
            #expect(sut.responseBody?.count == 1024)
            #expect(sut.responseSizeLabel == expectedLabel)
        }

        @Test("A body set whole is not truncated, and its size is its count")
        func wholeEntry() {
            var sut = NetworkEntry(
                timestamp: Date(timeIntervalSinceReferenceDate: 0), method: "GET", url: "", host: "", path: "",
                requestHeaders: [:], requestBody: nil, isComplete: true
            )
            let expectedSize = 2048

            sut.responseBody = Data(repeating: 0, count: 2048)

            #expect(sut.responseBodySize == expectedSize)
            #expect(!sut.isResponseBodyTruncated)
        }

        @Test("A truncated body leaves a HAR file without its text when the rules mask JSON keys, with its full size")
        func truncatedBodyWithheldFromArchive() {
            let entry = NetworkEntry(
                timestamp: Date(timeIntervalSinceReferenceDate: 0), method: "GET", url: "https://api.example.com/v1/users",
                host: "api.example.com", path: "/v1/users", requestHeaders: [:], requestBody: nil, statusCode: 200,
                responseBody: Data(#"{"token":"secret","users":["#.utf8), responseBodySize: 4096, isComplete: true
            )
            let expectedSize = 4096

            let actual = HTTPArchive.Entry(entry, original: nil, redaction: .standard)

            #expect(actual.response.content.text == nil)
            #expect(actual.response.content.size == expectedSize)
            #expect(actual.response.bodySize == expectedSize)
        }

        @Test("A truncated body is written to a HAR file as kept when no rule masks a JSON key or path, and reads back truncated")
        func truncatedBodyRoundTrips() throws {
            let kept = Data(#"{"users":["#.utf8)
            let entry = NetworkEntry(
                timestamp: Date(timeIntervalSinceReferenceDate: 0), method: "GET", url: "https://api.example.com/v1/users",
                host: "api.example.com", path: "/v1/users", requestHeaders: [:], requestBody: nil, statusCode: 200,
                responseBody: kept, responseBodySize: 4096, isComplete: true
            )
            let archived = HTTPArchive.Entry(entry, original: nil, redaction: .none)

            let actual = NetworkEntry(archived)

            #expect(actual.responseBody == kept)
            #expect(actual.responseBodySize == 4096)
            #expect(actual.isResponseBodyTruncated)
        }
    }
#endif
