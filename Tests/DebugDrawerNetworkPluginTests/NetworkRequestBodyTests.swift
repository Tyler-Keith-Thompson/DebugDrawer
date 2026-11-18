#if DEBUG
    @testable import DebugDrawerNetworkPlugin
    import DebugDrawer
    import Foundation
    import Testing

    @Suite
    struct NetworkRequestBodyTests {
        @Test("A stream within the limit is read whole into memory, and the log keeps all of it")
        func streamWithinLimitStaysInMemory() throws {
            let expected = Data("abcd".utf8)
            var request = URLRequest(url: URL(filePath: "/upload"))
            request.httpBodyStream = InputStream(data: expected)

            let sut = try #require(try NetworkRequestBody.read(from: request, limit: 4))

            guard case let .data(forwarded) = sut.source else {
                Issue.record("A body within the limit went to a file")
                return
            }
            #expect(forwarded == expected)
            #expect(sut.recorded == expected)
            #expect(sut.size == 4)
        }

        @Test("A stream one byte past the limit goes whole to a file, and the log keeps its first limit bytes")
        func streamPastLimitGoesToFile() throws {
            let expected = Data("abcde".utf8)
            let expectedRecorded = Data("abcd".utf8)
            var request = URLRequest(url: URL(filePath: "/upload"))
            request.httpBodyStream = InputStream(data: expected)

            let sut = try #require(try NetworkRequestBody.read(from: request, limit: 4))

            guard case let .file(file) = sut.source else {
                Issue.record("A body past the limit stayed in memory")
                return
            }
            let actual = try Data(contentsOf: file.url)
            #expect(actual == expected)
            #expect(sut.recorded == expectedRecorded)
            #expect(sut.size == 5)
        }

        @Test("A stream larger than the read buffer, past the limit, reaches the file whole and in order")
        func largeStreamReachesFileWhole() throws {
            let expected = Data((0 ..< 200_000).map { UInt8(ascii: "a") + UInt8($0 % 26) })
            var request = URLRequest(url: URL(filePath: "/upload"))
            request.httpBodyStream = InputStream(data: expected)

            let sut = try #require(try NetworkRequestBody.read(from: request, limit: 1000))

            guard case let .file(file) = sut.source else {
                Issue.record("A body past the limit stayed in memory")
                return
            }
            let actual = try Data(contentsOf: file.url)
            #expect(actual == expected)
            #expect(sut.recorded == expected.prefix(1000))
            #expect(sut.size == expected.count)
        }

        @Test("A limit of zero sends any streamed body to a file, and the log keeps none of it")
        func zeroLimit() throws {
            let expected = Data("a".utf8)
            var request = URLRequest(url: URL(filePath: "/upload"))
            request.httpBodyStream = InputStream(data: expected)

            let sut = try #require(try NetworkRequestBody.read(from: request, limit: 0))

            guard case let .file(file) = sut.source else {
                Issue.record("A body past the limit stayed in memory")
                return
            }
            #expect(try Data(contentsOf: file.url) == expected)
            #expect(sut.recorded?.isEmpty == true)
            #expect(sut.size == 1)
        }

        @Test("An empty stream is an empty body in memory, which the log records as no body")
        func emptyStream() throws {
            var request = URLRequest(url: URL(filePath: "/upload"))
            request.httpBodyStream = InputStream(data: Data())

            let sut = try #require(try NetworkRequestBody.read(from: request, limit: 4))

            guard case let .data(forwarded) = sut.source else {
                Issue.record("An empty body went to a file")
                return
            }
            #expect(forwarded.isEmpty)
            #expect(sut.recorded == nil)
            #expect(sut.size == 0)
        }

        @Test("A request with no body has none to read")
        func noBody() throws {
            let request = URLRequest(url: URL(filePath: "/upload"))

            let actual = try NetworkRequestBody.read(from: request, limit: 4)

            #expect(actual == nil)
        }

        @Test("A data body past the limit is forwarded whole, and the log keeps its first limit bytes")
        func dataBodyPastLimit() throws {
            let expected = Data("abcdef".utf8)
            let expectedRecorded = Data("abc".utf8)
            var request = URLRequest(url: URL(filePath: "/upload"))
            request.httpBody = expected

            let sut = try #require(try NetworkRequestBody.read(from: request, limit: 3))

            guard case let .data(forwarded) = sut.source else {
                Issue.record("A data body went to a file")
                return
            }
            #expect(forwarded == expected)
            #expect(sut.recorded == expectedRecorded)
            #expect(sut.size == 6)
        }

        @Test("Forwarding a body in a file streams it from the file, with a Content-Length of its size")
        func forwardsFileWithLength() throws {
            let expected = Data("abcdefgh".utf8)
            var request = URLRequest(url: URL(filePath: "/upload"))
            request.httpBodyStream = InputStream(data: expected)
            let sut = try #require(try NetworkRequestBody.read(from: request, limit: 2))
            let forwarded = try #require((request as NSURLRequest).mutableCopy() as? NSMutableURLRequest)

            sut.forward(in: forwarded)

            let stream = try #require(forwarded.httpBodyStream)
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 64)
            let count = stream.read(&buffer, maxLength: buffer.count)
            #expect(Data(buffer.prefix(max(count, 0))) == expected)
            #expect(forwarded.value(forHTTPHeaderField: "Content-Length") == "8")
            #expect(forwarded.httpBody == nil)
        }

        @Test("Forwarding a body in memory sets it as the request's body, in place of the used-up stream")
        func forwardsDataInPlaceOfStream() throws {
            let expected = Data("abc".utf8)
            var request = URLRequest(url: URL(filePath: "/upload"))
            request.httpBodyStream = InputStream(data: expected)
            let sut = try #require(try NetworkRequestBody.read(from: request, limit: 16))
            let forwarded = try #require((request as NSURLRequest).mutableCopy() as? NSMutableURLRequest)

            sut.forward(in: forwarded)

            #expect(forwarded.httpBody == expected)
            #expect(forwarded.httpBodyStream == nil)
        }

        @Test("A body's temporary file is removed once nothing holds it")
        func removesFile() throws {
            var request = URLRequest(url: URL(filePath: "/upload"))
            request.httpBodyStream = InputStream(data: Data("abcdef".utf8))
            var sut = try NetworkRequestBody.read(from: request, limit: 2)
            // The file is bound only inside the `if`, so nothing but `sut` holds it after.
            let found: String? = if case let .file(file)? = sut?.source { file.url.path(percentEncoded: false) } else { nil }
            let path = try #require(found)
            #expect(FileManager.default.fileExists(atPath: path))

            sut = nil

            #expect(!FileManager.default.fileExists(atPath: path))
        }

        @Test("A truncated request body is withheld from a HAR file when the rules mask JSON keys, with its full size")
        func truncatedRequestWithheldFromArchive() {
            let entry = NetworkEntry(
                timestamp: Date(timeIntervalSinceReferenceDate: 0), method: "POST", url: "https://api.example.com/v1/login",
                host: "api.example.com", path: "/v1/login", requestHeaders: [:], requestBody: Data(#"{"password":"sec"#.utf8),
                requestBodySize: 4096, isComplete: true
            )
            let expectedSize = 4096

            let actual = HTTPArchive.Entry(entry, original: nil, redaction: .standard)

            #expect(entry.isRequestBodyTruncated)
            #expect(actual.request.postData == nil)
            #expect(actual.request.bodySize == expectedSize)
        }
    }
#endif
