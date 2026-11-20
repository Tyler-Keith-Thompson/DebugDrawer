#if DEBUG
    import DebugDrawerMetricKit
    @testable import DebugDrawerMetricKitPlugin
    import Foundation
    import Testing

    @MainActor
    @Suite
    struct MetricKitPayloadStoreTests {
        @Test("A received payload is kept unseen with its kind, period, arrival and JSON, keys sorted, and raises the badge")
        func receive() throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            var counts: [Int] = []
            let sut = MetricKitPayloadStore(directory: directory) { counts.append($0) }
            let begin = Date(timeIntervalSince1970: 1_763_164_800)
            let end = Date(timeIntervalSince1970: 1_763_251_200)
            let received = Date(timeIntervalSince1970: 1_763_290_000)
            let incoming = ReceivedMetricKitPayload(kind: .metrics, json: Data(#"{"b":1,"a":{"d":2,"c":3}}"#.utf8), begin: begin, end: end)
            let expectedJSON = Data(#"{"a":{"c":3,"d":2},"b":1}"#.utf8)

            let actual = sut.receive([incoming], at: received)

            let payload = try #require(actual.first)
            #expect(actual.count == 1)
            #expect(payload.kind == .metrics)
            #expect(payload.begin == begin)
            #expect(payload.end == end)
            #expect(payload.received == received)
            #expect(payload.json == expectedJSON)
            #expect(!payload.isSeen)
            #expect(sut.payloads == actual)
            #expect(counts == [1])
        }

        @Test("History survives a relaunch: a new store over the same directory lists the same payloads")
        func relaunch() {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let sut = MetricKitPayloadStore(directory: directory)
            sut.receive([
                ReceivedMetricKitPayload(
                    kind: .metrics, json: Data(#"{"appVersion":"1.0"}"#.utf8),
                    begin: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 1)
                ),
                ReceivedMetricKitPayload(
                    kind: .diagnostics, json: Data(#"{"crashDiagnostics":[]}"#.utf8),
                    begin: Date(timeIntervalSince1970: 1), end: Date(timeIntervalSince1970: 2)
                )
            ])
            let expected = sut.payloads

            let actual = MetricKitPayloadStore(directory: directory).payloads

            #expect(actual == expected)
            #expect(actual.map(\.kind) == [.diagnostics, .metrics])
        }

        @Test("Without a period from the sender, the payload's own timestamps give it, as MetricKit writes them or in ISO 8601")
        func timestampsFromJSON() throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let sut = MetricKitPayloadStore(directory: directory)
            let json = #"{"timeStampBegin":"2025-11-15 00:00:00 +0000","timeStampEnd":"2025-11-16T00:00:00Z"}"#
            let expectedBegin = Date(timeIntervalSince1970: 1_763_164_800)
            let expectedEnd = Date(timeIntervalSince1970: 1_763_251_200)

            let actual = try #require(sut.receive([ReceivedMetricKitPayload(kind: .metrics, json: Data(json.utf8))]).first)

            #expect(actual.begin == expectedBegin)
            #expect(actual.end == expectedEnd)
        }

        @Test("A payload with no period anywhere covers the moment it arrived")
        func noTimestamps() throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let sut = MetricKitPayloadStore(directory: directory)
            let received = Date(timeIntervalSince1970: 1_763_290_000)

            let incoming = ReceivedMetricKitPayload(kind: .diagnostics, json: Data(#"{"timeStampEnd":"soon"}"#.utf8))

            let actual = try #require(sut.receive([incoming], at: received).first)

            #expect(actual.begin == received)
            #expect(actual.end == received)
        }

        @Test("The same payload delivered again, keys in another order, is kept once; the same JSON of the other kind is kept apart")
        func dedupe() {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            var counts: [Int] = []
            let sut = MetricKitPayloadStore(directory: directory) { counts.append($0) }
            let first = ReceivedMetricKitPayload(kind: .metrics, json: Data(#"{"a":1,"b":2}"#.utf8))
            let reordered = ReceivedMetricKitPayload(kind: .metrics, json: Data(#"{ "b" : 2, "a" : 1 }"#.utf8))
            let otherKind = ReceivedMetricKitPayload(kind: .diagnostics, json: Data(#"{"a":1,"b":2}"#.utf8))
            sut.receive([first])

            let again = sut.receive([reordered, reordered])
            let relaunched = MetricKitPayloadStore(directory: directory).receive([first])
            let actual = sut.receive([otherKind])

            #expect(again.isEmpty)
            #expect(relaunched.isEmpty)
            #expect(actual.map(\.kind) == [.diagnostics])
            #expect(sut.payloads.count == 2)
            #expect(counts == [1, 2])
        }

        @Test("JSON that isn't an object is dropped")
        func garbageJSON() {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            var counts: [Int] = []
            let sut = MetricKitPayloadStore(directory: directory) { counts.append($0) }

            let actual = sut.receive([
                ReceivedMetricKitPayload(kind: .metrics, json: Data("not json".utf8)),
                ReceivedMetricKitPayload(kind: .metrics, json: Data("[1, 2]".utf8)),
                ReceivedMetricKitPayload(kind: .metrics, json: Data())
            ])

            #expect(actual.isEmpty)
            #expect(sut.payloads.isEmpty)
            #expect(counts.isEmpty)
        }

        @Test("Files in the directory that aren't payloads are skipped on load")
        func garbageFiles() throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let sut = MetricKitPayloadStore(directory: directory)
            sut.receive([ReceivedMetricKitPayload(kind: .metrics, json: Data("{}".utf8))])
            try Data("garbage".utf8).write(to: directory.appending(path: "\(UUID().uuidString).json"))
            try Data(#"{"id":"x"}"#.utf8).write(to: directory.appending(path: "partial.json"))
            try Data("notes".utf8).write(to: directory.appending(path: "notes.txt"))
            let expected = sut.payloads

            let actual = MetricKitPayloadStore(directory: directory).payloads

            #expect(actual == expected)
        }

        @Test("Payloads are listed the latest period first, and only the newest fifty are kept, on disk too")
        func keepsNewest() {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let sut = MetricKitPayloadStore(directory: directory)
            let incoming = (0 ..< 52).map { (day: Int) -> ReceivedMetricKitPayload in
                let json: String = #"{"day":\#(day)}"#
                let begin = Date(timeIntervalSince1970: TimeInterval(day * 86400))
                let end = Date(timeIntervalSince1970: TimeInterval((day + 1) * 86400))
                return ReceivedMetricKitPayload(kind: .metrics, json: Data(json.utf8), begin: begin, end: end)
            }
            let expectedEnds = (2 ..< 52).reversed().map { (day: Int) -> Date in Date(timeIntervalSince1970: TimeInterval((day + 1) * 86400)) }

            for payload in incoming.shuffled() {
                sut.receive([payload])
            }

            #expect(sut.payloads.map(\.end) == expectedEnds)
            #expect(MetricKitPayloadStore(directory: directory).payloads.map(\.end) == expectedEnds)
            let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))) ?? []
            #expect(files.count == 50)
        }

        @Test("A payload older than the newest fifty isn't kept, and isn't reported as new")
        func olderThanLimit() {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let sut = MetricKitPayloadStore(directory: directory)
            sut.receive((1 ... 50).map { day in
                ReceivedMetricKitPayload(
                    kind: .metrics, json: Data(#"{"day":\#(day)}"#.utf8), begin: .distantPast, end: Date(timeIntervalSince1970: TimeInterval(day))
                )
            })

            let older = ReceivedMetricKitPayload(
                kind: .metrics, json: Data(#"{"day":0}"#.utf8), begin: .distantPast, end: Date(timeIntervalSince1970: 0)
            )

            let actual = sut.receive([older])

            #expect(actual.isEmpty)
            #expect(sut.payloads.count == 50)
            #expect(MetricKitPayloadStore(directory: directory).payloads.count == 50)
        }

        @Test("Opening a payload marks it seen, which lowers the badge and lasts across launches")
        func markSeen() throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            var counts: [Int] = []
            let sut = MetricKitPayloadStore(directory: directory) { counts.append($0) }
            sut.receive([
                ReceivedMetricKitPayload(kind: .metrics, json: Data(#"{"day":1}"#.utf8), begin: .distantPast, end: Date(timeIntervalSince1970: 1)),
                ReceivedMetricKitPayload(kind: .metrics, json: Data(#"{"day":2}"#.utf8), begin: .distantPast, end: Date(timeIntervalSince1970: 2))
            ])
            let older = try #require(sut.payloads.last)

            sut.markSeen(older.id)

            #expect(sut.unseenCount == 1)
            #expect(counts == [2, 1])
            #expect(MetricKitPayloadStore(directory: directory).payloads.map(\.isSeen) == [false, true])
        }

        @Test("Mark All Seen clears the badge, across launches too")
        func markAllSeen() {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            var counts: [Int] = []
            let sut = MetricKitPayloadStore(directory: directory) { counts.append($0) }
            sut.receive([
                ReceivedMetricKitPayload(kind: .metrics, json: Data(#"{"day":1}"#.utf8)),
                ReceivedMetricKitPayload(kind: .diagnostics, json: Data(#"{"day":1}"#.utf8))
            ])

            sut.markAllSeen()

            #expect(sut.unseenCount == 0)
            #expect(counts.last == 0)
            #expect(MetricKitPayloadStore(directory: directory).unseenCount == 0)
        }

        @Test("Deleting a payload removes it, from disk too, and Delete All removes the rest")
        func delete() throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            var counts: [Int] = []
            let sut = MetricKitPayloadStore(directory: directory) { counts.append($0) }
            sut.receive((1 ... 3).map { day in
                ReceivedMetricKitPayload(
                    kind: .metrics, json: Data(#"{"day":\#(day)}"#.utf8), begin: .distantPast, end: Date(timeIntervalSince1970: TimeInterval(day))
                )
            })
            let ids = sut.payloads.map(\.id)

            sut.delete(ids[1])

            #expect(sut.payloads.map(\.id) == [ids[0], ids[2]])
            #expect(MetricKitPayloadStore(directory: directory).payloads.map(\.id) == [ids[0], ids[2]])

            sut.deleteAll()

            #expect(sut.payloads.isEmpty)
            #expect(MetricKitPayloadStore(directory: directory).payloads.isEmpty)
            #expect(counts == [3, 2, 0])
        }

        @Test("A deleted payload delivered again is kept again")
        func deletedThenRedelivered() throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let sut = MetricKitPayloadStore(directory: directory)
            let incoming = ReceivedMetricKitPayload(kind: .metrics, json: Data("{}".utf8))
            let first = try #require(sut.receive([incoming]).first)
            sut.delete(first.id)

            let actual = sut.receive([incoming])

            #expect(actual.count == 1)
        }

        @Test("An empty directory, or one that doesn't exist yet, lists no payloads")
        func empty() {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).appending(path: "nested")
            defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }

            let sut = MetricKitPayloadStore(directory: directory)

            #expect(sut.payloads.isEmpty)
            #expect(sut.unseenCount == 0)
            #expect(FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)))
        }
    }
#endif
