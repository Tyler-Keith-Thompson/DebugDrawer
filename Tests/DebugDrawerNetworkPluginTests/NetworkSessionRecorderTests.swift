#if DEBUG
    import DebugDrawer
    @testable import DebugDrawerNetworkPlugin
    import Foundation
    import Testing

    // The production file storage, in a temporary directory of the test's own; each recorder made
    // over a directory is a launch of the app. Listing the earlier sessions runs on the recorder's
    // queue after every record before it, so a test awaits it before it looks at the disk.
    @Suite(.timeLimit(.minutes(1)))
    struct NetworkSessionRecorderTests {
        @Test("Requests one launch records are listed, with their requests, as a previous session by a recorder made over the same directory")
        func previousSessionAfterRelaunch() async throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            defer { try? FileManager.default.removeItem(at: directory) }
            let persistence = try NetworkSessionPersistence(storage: _NetworkSessionStorage(directory: directory))
            let started = Date(timeIntervalSince1970: 1_800_000_000)
            let first = NetworkSessionRecorder(persistence, started: started)
            let orders = NetworkEntry(
                timestamp: Date(timeIntervalSince1970: 1_800_000_001), method: "GET", url: "https://api.example.com/v1/orders",
                host: "api.example.com", path: "/v1/orders", requestHeaders: [:], requestBody: nil, statusCode: 200, isComplete: true
            )
            let failed = NetworkEntry(
                timestamp: Date(timeIntervalSince1970: 1_800_000_002), method: "POST", url: "https://api.example.com/v1/cart",
                host: "api.example.com", path: "/v1/cart", requestHeaders: [:], requestBody: nil, error: "The network connection was lost.",
                isComplete: true
            )
            first.record(orders, original: nil, redaction: .standard)
            first.record(failed, original: nil, redaction: .standard)
            let firstSees = await first.previousSessions()

            let sut = NetworkSessionRecorder(persistence, started: Date(timeIntervalSince1970: 1_800_000_100))
            let sessions = await sut.previousSessions()
            let session = try #require(sessions.first)
            let actual = try await sut.log(of: session)

            #expect(firstSees.isEmpty)
            #expect(sessions.count == 1)
            #expect(session.id == first.currentName)
            #expect(session.started == started)
            #expect(actual.header?.started == "2027-01-15T08:00:00.000Z")
            #expect(actual.entries.map(\.url) == ["https://api.example.com/v1/cart", "https://api.example.com/v1/orders"])
            #expect(actual.entries.map(\.statusCode) == [nil, 200])
            #expect(actual.entries.first?.error == "The network connection was lost.")
            #expect(actual.skippedLines == 0)
        }

        @Test("A session with a torn last line, as a crash mid-write leaves it, reads every line before it and counts the torn one")
        func tornLastLine() async throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            defer { try? FileManager.default.removeItem(at: directory) }
            let storage = _NetworkSessionStorage(directory: directory)
            let persistence = try NetworkSessionPersistence(storage: storage)
            let first = NetworkSessionRecorder(persistence, started: Date(timeIntervalSince1970: 1_800_000_000))
            for index in 1 ... 2 {
                first.record(
                    NetworkEntry(
                        timestamp: Date(timeIntervalSince1970: 1_800_000_000 + Double(index)), method: "GET",
                        url: "https://api.example.com/\(index)", host: "api.example.com", path: "/\(index)", requestHeaders: [:],
                        requestBody: nil, statusCode: 200, isComplete: true
                    ),
                    original: nil,
                    redaction: .standard
                )
            }
            _ = await first.previousSessions()
            try storage.append(Data(#"{"startedDateTime":"2027-01-15T08:00:03.000Z","request":{"meth"#.utf8), toSessionNamed: first.currentName)

            let sut = NetworkSessionRecorder(persistence, started: Date(timeIntervalSince1970: 1_800_000_100))
            let session = try #require(await sut.previousSessions().first)
            let actual = try await sut.log(of: session)

            #expect(actual.entries.map(\.url) == ["https://api.example.com/2", "https://api.example.com/1"])
            #expect(actual.skippedLines == 1)
        }

        @Test("The values the redaction rules mask in headers, the query and JSON bodies never reach the disk")
        func redactedOnDisk() async throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            defer { try? FileManager.default.removeItem(at: directory) }
            let storage = _NetworkSessionStorage(directory: directory)
            let sut = NetworkSessionRecorder(try NetworkSessionPersistence(storage: storage), started: Date(timeIntervalSince1970: 1_800_000_000))
            let entry = NetworkEntry(
                timestamp: Date(timeIntervalSince1970: 1_800_000_001), method: "POST",
                url: "https://api.example.com/v1/login?api_key=query-secret-1", host: "api.example.com", path: "/v1/login",
                requestHeaders: ["Authorization": "Bearer header-secret-2", "Cookie": "session=cookie-secret-3"],
                requestBody: Data(#"{"user":"ada","password":"body-secret-4"}"#.utf8),
                statusCode: 200, responseHeaders: ["Content-Type": "application/json"],
                responseBody: Data(#"{"token":"response-secret-5","name":"Ada"}"#.utf8), isComplete: true
            )

            sut.record(entry, original: nil, redaction: .standard)
            _ = await sut.previousSessions()

            let written = try (String(bytes: Data(contentsOf: directory.appending(path: sut.currentName)), encoding: .utf8) ?? "")
            for secret in ["query-secret-1", "header-secret-2", "cookie-secret-3", "body-secret-4", "response-secret-5"] {
                #expect(!written.contains(secret), "\(secret) was written")
            }
            #expect(written.contains(DebugDrawerRedaction.mask))
            #expect(written.contains("Ada"))
        }

        @Test("Each launch deletes the oldest sessions beyond maxSessions, keeping the newest")
        func pruneByCount() async throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            defer { try? FileManager.default.removeItem(at: directory) }
            let persistence = try NetworkSessionPersistence(maxSessions: 2, storage: _NetworkSessionStorage(directory: directory))
            var names: [String] = []
            for launch in 0 ..< 4 {
                let recorder = NetworkSessionRecorder(persistence, started: Date(timeIntervalSince1970: 1_800_000_000 + Double(launch) * 60))
                recorder.record(
                    NetworkEntry(
                        timestamp: Date(timeIntervalSince1970: 1_800_000_001 + Double(launch) * 60), method: "GET",
                        url: "https://api.example.com/\(launch)", host: "api.example.com", path: "/\(launch)", requestHeaders: [:],
                        requestBody: nil, statusCode: 200, isComplete: true
                    ),
                    original: nil,
                    redaction: .standard
                )
                _ = await recorder.previousSessions()
                names.append(recorder.currentName)
            }
            let expected = [names[3], names[2]]

            let sut = NetworkSessionRecorder(persistence, started: Date(timeIntervalSince1970: 1_800_001_000))
            let actual = await sut.previousSessions().map(\.id)
            let files = try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))

            #expect(actual == expected)
            #expect(files.sorted() == expected.sorted())
        }

        @Test("Once the current session's writes take the sessions past maxBytes, the oldest earlier session is deleted, and only it")
        func pruneBySizeWhileWriting() async throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            defer { try? FileManager.default.removeItem(at: directory) }
            let storage = _NetworkSessionStorage(directory: directory)
            let roomy = try NetworkSessionPersistence(storage: storage)
            let entry = NetworkEntry(
                timestamp: Date(timeIntervalSince1970: 1_800_000_001), method: "GET", url: "https://api.example.com/v1/orders",
                host: "api.example.com", path: "/v1/orders", requestHeaders: [:], requestBody: nil, statusCode: 200, isComplete: true
            )
            let oldest = NetworkSessionRecorder(roomy, started: Date(timeIntervalSince1970: 1_800_000_000))
            oldest.record(entry, original: nil, redaction: .standard)
            _ = await oldest.previousSessions()
            let newer = NetworkSessionRecorder(roomy, started: Date(timeIntervalSince1970: 1_800_000_060))
            newer.record(entry, original: nil, redaction: .standard)
            _ = await newer.previousSessions()
            let sizes = try storage.sessionFiles().reduce(into: [String: Int]()) { $0[$1.name] = $1.byteCount }
            let oldestBytes = try #require(sizes[oldest.currentName])
            let newerBytes = try #require(sizes[newer.currentName])
            // Room for both sessions at launch, and for the next one's header and entry, as large
            // as either's, only once one goes.
            let tight = try NetworkSessionPersistence(maxBytes: oldestBytes + newerBytes + 10, storage: storage)

            let sut = NetworkSessionRecorder(tight, started: Date(timeIntervalSince1970: 1_800_000_120))
            let atLaunch = await sut.previousSessions().map(\.id)
            sut.record(entry, original: nil, redaction: .standard)
            let afterWriting = await sut.previousSessions().map(\.id)
            let current = try storage.sessionFiles().first { $0.name == sut.currentName }

            #expect(atLaunch == [newer.currentName, oldest.currentName])
            #expect(afterWriting == [newer.currentName])
            #expect(current?.byteCount == oldestBytes)
        }

        @Test("A launch deletes the oldest sessions until those kept fit in maxBytes")
        func pruneBySizeAtLaunch() async throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            defer { try? FileManager.default.removeItem(at: directory) }
            let storage = _NetworkSessionStorage(directory: directory)
            let entry = NetworkEntry(
                timestamp: Date(timeIntervalSince1970: 1_800_000_001), method: "GET", url: "https://api.example.com/v1/orders",
                host: "api.example.com", path: "/v1/orders", requestHeaders: [:], requestBody: nil, statusCode: 200, isComplete: true
            )
            var names: [String] = []
            for launch in 0 ..< 3 {
                let recorder = NetworkSessionRecorder(
                    try NetworkSessionPersistence(storage: storage),
                    started: Date(timeIntervalSince1970: 1_800_000_000 + Double(launch) * 60)
                )
                recorder.record(entry, original: nil, redaction: .standard)
                _ = await recorder.previousSessions()
                names.append(recorder.currentName)
            }
            let largest = try storage.sessionFiles().map(\.byteCount).max() ?? 0
            let expected = [names[2]]

            let sut = NetworkSessionRecorder(
                try NetworkSessionPersistence(maxBytes: largest + 1, storage: storage),
                started: Date(timeIntervalSince1970: 1_800_001_000)
            )
            let actual = await sut.previousSessions().map(\.id)

            #expect(actual == expected)
        }

        @Test("A current session that alone would pass maxBytes keeps the requests that fit, within the limit, and is never deleted")
        func currentSessionTruncated() async throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            defer { try? FileManager.default.removeItem(at: directory) }
            let storage = _NetworkSessionStorage(directory: directory)
            let maxBytes = 1_500
            let sut = NetworkSessionRecorder(
                try NetworkSessionPersistence(maxBytes: maxBytes, storage: storage),
                started: Date(timeIntervalSince1970: 1_800_000_000)
            )
            let recorded = (0 ..< 10).map { index in
                NetworkEntry(
                    timestamp: Date(timeIntervalSince1970: 1_800_000_001 + Double(index)), method: "GET",
                    url: "https://api.example.com/v1/orders/\(index)", host: "api.example.com", path: "/v1/orders/\(index)",
                    requestHeaders: [:], requestBody: nil, statusCode: 200, isComplete: true
                )
            }

            for entry in recorded {
                sut.record(entry, original: nil, redaction: .standard)
                // One at a time, so each is its own write.
                _ = await sut.previousSessions()
            }
            let file = try #require(try storage.sessionFiles().first { $0.name == sut.currentName })
            let summary = try #require(NetworkSessionSummary(file))
            let actual = NetworkSessionLog(summary: summary, data: try storage.contents(ofSessionNamed: sut.currentName))
            let kept = actual.entries.map(\.url).reversed()

            #expect(file.byteCount <= maxBytes)
            #expect(!kept.isEmpty)
            #expect(kept.count < recorded.count)
            #expect(Array(kept) == recorded.prefix(kept.count).map(\.url))
        }

        @Test("A request too large for the room left isn't written, and a smaller one after it is")
        func oversizedRequestSkipped() async throws {
            let storage = FakeNetworkSessionStorage()
            let sut = NetworkSessionRecorder(
                try NetworkSessionPersistence(maxBytes: 3_000, storage: storage),
                started: Date(timeIntervalSince1970: 1_800_000_000)
            )
            let download = NetworkEntry(
                timestamp: Date(timeIntervalSince1970: 1_800_000_001), method: "GET", url: "https://cdn.example.com/video.json",
                host: "cdn.example.com", path: "/video.json", requestHeaders: [:], requestBody: nil, statusCode: 200,
                responseBody: Data(repeating: UInt8(ascii: "a"), count: 10_000), isComplete: true
            )
            let ping = NetworkEntry(
                timestamp: Date(timeIntervalSince1970: 1_800_000_002), method: "GET", url: "https://api.example.com/ping",
                host: "api.example.com", path: "/ping", requestHeaders: [:], requestBody: nil, statusCode: 204, isComplete: true
            )

            sut.record(download, original: nil, redaction: .standard)
            _ = await sut.previousSessions()
            sut.record(ping, original: nil, redaction: .standard)
            _ = await sut.previousSessions()
            let data = try storage.contents(ofSessionNamed: sut.currentName)
            let summary = try #require(NetworkSessionSummary(NetworkSessionFile(name: sut.currentName, byteCount: data.count)))
            let actual = NetworkSessionLog(summary: summary, data: data)

            #expect(actual.header != nil)
            #expect(actual.entries.map(\.url) == ["https://api.example.com/ping"])
            #expect(data.count <= 3_000)
        }

        @Test("Off, nothing is written and the sessions earlier launches kept are deleted at launch")
        func off() async throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            defer { try? FileManager.default.removeItem(at: directory) }
            let storage = _NetworkSessionStorage(directory: directory)
            let entry = NetworkEntry(
                timestamp: Date(timeIntervalSince1970: 1_800_000_001), method: "GET", url: "https://api.example.com/v1/orders",
                host: "api.example.com", path: "/v1/orders", requestHeaders: [:], requestBody: nil, statusCode: 200, isComplete: true
            )
            let earlier = NetworkSessionRecorder(try NetworkSessionPersistence(storage: storage), started: Date(timeIntervalSince1970: 1_800_000_000))
            earlier.record(entry, original: nil, redaction: .standard)
            _ = await earlier.previousSessions()
            let before = try storage.sessionFiles().count

            let sut = NetworkSessionRecorder(

                try NetworkSessionPersistence(maxSessions: 0, storage: storage),

                started: Date(timeIntervalSince1970: 1_800_000_060)

            )
            sut.record(entry, original: nil, redaction: .standard)
            let listed = await sut.previousSessions()
            let actual = try storage.sessionFiles()

            #expect(before == 1)
            #expect(listed.isEmpty)
            #expect(actual.isEmpty)
            #expect(NetworkSessionPersistence.off.maxSessions == 0)
        }

        @Test("Requests recorded from many tasks at once are each written once, as a whole line")
        func concurrentRecords() async throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            defer { try? FileManager.default.removeItem(at: directory) }
            let persistence = try NetworkSessionPersistence(storage: _NetworkSessionStorage(directory: directory))
            let sut = NetworkSessionRecorder(persistence, started: Date(timeIntervalSince1970: 1_800_000_000), capacity: 1_000)
            let count = 300
            let expected = Set((0 ..< count).map { "https://api.example.com/\($0)" })

            await withTaskGroup(of: Void.self) { group in
                for index in 0 ..< count {
                    group.addTask {
                        sut.record(
                            NetworkEntry(
                                timestamp: Date(timeIntervalSince1970: 1_800_000_000), method: "GET", url: "https://api.example.com/\(index)",
                                host: "api.example.com", path: "/\(index)", requestHeaders: [:], requestBody: nil, statusCode: 200,
                                isComplete: true
                            ),
                            original: nil,
                            redaction: .standard
                        )
                    }
                }
            }
            _ = await sut.previousSessions()
            let next = NetworkSessionRecorder(persistence, started: Date(timeIntervalSince1970: 1_800_000_060))
            let session = try #require(await next.previousSessions().first)
            let actual = try await next.log(of: session)

            #expect(actual.entries.count == count)
            #expect(Set(actual.entries.map(\.url)) == expected)
            #expect(actual.skippedLines == 0)
        }

        @Test("While a write is slow, at most capacity requests wait, the earliest going first")
        func boundedWhileWriting() async throws {
            let storage = FakeNetworkSessionStorage(holdsAppends: true)
            let sut = NetworkSessionRecorder(
                try NetworkSessionPersistence(storage: storage),
                started: Date(timeIntervalSince1970: 1_800_000_000), capacity: 3
            )
            var started = storage.appendsStarted.makeAsyncIterator()
            func entry(_ index: Int) -> NetworkEntry {
                NetworkEntry(
                    timestamp: Date(timeIntervalSince1970: 1_800_000_000 + Double(index)), method: "GET", url: "https://api.example.com/\(index)",
                    host: "api.example.com", path: "/\(index)", requestHeaders: [:], requestBody: nil, statusCode: 200, isComplete: true
                )
            }
            sut.record(entry(0), original: nil, redaction: .standard)
            await started.next()
            for index in 1 ... 10 {
                sut.record(entry(index), original: nil, redaction: .standard)
            }

            storage.releaseAppend()
            await started.next()
            storage.releaseAppend()
            _ = await sut.previousSessions()
            let summary = try #require(NetworkSessionSummary(NetworkSessionFile(name: sut.currentName, byteCount: 0)))
            let actual = NetworkSessionLog(summary: summary, data: try storage.contents(ofSessionNamed: sut.currentName))

            let expected = ["0", "8", "9", "10"].map { "https://api.example.com/\($0)" }

            #expect(Array(actual.entries.map(\.url).reversed()) == expected)
        }

        @Test("A WebSocket connection that ended is written as its handshake, and the file starts with the session's header")
        func webSocketAndHeader() async throws {
            let storage = FakeNetworkSessionStorage()
            let started = Date(timeIntervalSince1970: 1_800_000_000)
            let sut = NetworkSessionRecorder(try NetworkSessionPersistence(storage: storage), started: started)
            var connection = NetworkWebSocketConnection(url: "wss://stream.example.com/prices?token=socket-secret", opened: started)
            connection.end(.failed(message: "The network connection was lost.", at: started.addingTimeInterval(2)))

            sut.record(connection, redaction: .standard)
            _ = await sut.previousSessions()
            let data = try storage.contents(ofSessionNamed: sut.currentName)
            let firstLine = try #require(data.split(separator: UInt8(ascii: "\n")).first)
            let header = try JSONDecoder().decode(NetworkSessionHeader.self, from: Data(firstLine))
            let summary = try #require(NetworkSessionSummary(NetworkSessionFile(name: sut.currentName, byteCount: data.count)))
            let actual = NetworkSessionLog(summary: summary, data: data)

            #expect(header.format == 1)
            #expect(header.started == "2027-01-15T08:00:00.000Z")
            #expect(actual.entries.count == 1)
            #expect(actual.entries.first?.url.hasPrefix("wss://stream.example.com/prices?token=") == true)
            // It failed before any frame, so as a request with no answer.
            #expect(actual.entries.first?.statusCode == nil)
            #expect(!(String(bytes: data, encoding: .utf8) ?? "").contains("socket-secret"))
        }

        @Test("Deleting removes the earlier sessions named, and never the current one")
        func delete() async throws {
            let storage = FakeNetworkSessionStorage()
            let entry = NetworkEntry(
                timestamp: Date(timeIntervalSince1970: 1_800_000_001), method: "GET", url: "https://api.example.com/v1/orders",
                host: "api.example.com", path: "/v1/orders", requestHeaders: [:], requestBody: nil, statusCode: 200, isComplete: true
            )
            let earlier = NetworkSessionRecorder(try NetworkSessionPersistence(storage: storage), started: Date(timeIntervalSince1970: 1_800_000_000))
            earlier.record(entry, original: nil, redaction: .standard)
            _ = await earlier.previousSessions()
            let sut = NetworkSessionRecorder(try NetworkSessionPersistence(storage: storage), started: Date(timeIntervalSince1970: 1_800_000_060))
            sut.record(entry, original: nil, redaction: .standard)

            await sut.delete([earlier.currentName, sut.currentName])
            let listed = await sut.previousSessions()

            #expect(listed.isEmpty)
            #expect(Array(storage.sessions.keys) == [sut.currentName])
        }
    }
#endif
