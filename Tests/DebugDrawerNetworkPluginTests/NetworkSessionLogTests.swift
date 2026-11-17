#if DEBUG
    import DebugDrawer
    @testable import DebugDrawerNetworkPlugin
    import Foundation
    import Testing

    @Suite
    struct NetworkSessionLogTests {
        @Test("A file with no header, as one deleted and started again mid-session, still reads its entries")
        func noHeader() throws {
            let entry = NetworkEntry(
                timestamp: Date(timeIntervalSince1970: 1_800_000_001), method: "GET", url: "https://api.example.com/v1/orders",
                host: "api.example.com", path: "/v1/orders", requestHeaders: [:], requestBody: nil, statusCode: 200, isComplete: true
            )
            let data = try JSONEncoder().encode(HTTPArchive.Entry(entry, original: nil, redaction: .standard)) + Data("\n".utf8)
            let summary = try #require(NetworkSessionSummary(NetworkSessionFile(
                name: NetworkSessionSummary.name(started: Date(timeIntervalSince1970: 1_800_000_000), id: UUID()), byteCount: data.count
            )))

            let actual = NetworkSessionLog(summary: summary, data: data)

            #expect(actual.header == nil)
            #expect(actual.entries.map(\.url) == ["https://api.example.com/v1/orders"])
            #expect(actual.skippedLines == 0)
        }

        @Test("A file whose header names a later format reads as empty, its lines counted unreadable")
        func laterFormat() throws {
            let header = Data(#"{"debugDrawerNetworkSession":2,"started":"2027-01-15T08:00:00.000Z","app":"Shop","appVersion":""}"#.utf8)
            let data = header + Data("\n".utf8) + Data(#"{"something":"new"}"#.utf8) + Data("\n".utf8)
            let summary = try #require(NetworkSessionSummary(NetworkSessionFile(
                name: NetworkSessionSummary.name(started: Date(timeIntervalSince1970: 1_800_000_000), id: UUID()), byteCount: data.count
            )))

            let actual = NetworkSessionLog(summary: summary, data: data)

            #expect(actual.header?.format == 2)
            #expect(actual.entries.isEmpty)
            #expect(actual.skippedLines == 1)
        }

        @Test("A session's name starts with its start, so names sort as sessions started, and reads back to it")
        func names() throws {
            let earlier = Date(timeIntervalSince1970: 1_800_000_000.25)
            let later = Date(timeIntervalSince1970: 1_800_000_060)
            let earlierName = NetworkSessionSummary.name(started: earlier, id: UUID())
            let laterName = NetworkSessionSummary.name(started: later, id: UUID())

            let actual = try #require(NetworkSessionSummary(NetworkSessionFile(name: earlierName, byteCount: 10)))

            #expect(earlierName.hasPrefix("2027-01-15T080000.250Z-"))
            #expect(earlierName.hasSuffix(".jsonl"))
            #expect(earlierName < laterName)
            #expect(actual.started == earlier)
            #expect(NetworkSessionSummary(NetworkSessionFile(name: "notes.jsonl", byteCount: 10)) == nil)
            #expect(NetworkSessionSummary(NetworkSessionFile(name: "2027-01-15T080000.250Z-x.txt", byteCount: 10)) == nil)
        }

        @Test("The report gets the newest earlier session as network-previous.har, its entries as written; none adds nothing")
        func report() throws {
            let entry = NetworkEntry(
                timestamp: Date(timeIntervalSince1970: 1_800_000_001), method: "GET", url: "https://api.example.com/v1/orders",
                host: "api.example.com", path: "/v1/orders", requestHeaders: ["Authorization": "Bearer report-secret"], requestBody: nil,
                statusCode: 200, isComplete: true
            )
            let line = try JSONEncoder().encode(HTTPArchive.Entry(entry, original: nil, redaction: .standard)) + Data("\n".utf8)
            let summary = try #require(NetworkSessionSummary(NetworkSessionFile(
                name: NetworkSessionSummary.name(started: Date(timeIntervalSince1970: 1_800_000_000), id: UUID()), byteCount: line.count
            )))
            var report = DebugDrawerReport()
            var empty = DebugDrawerReport()

            NetworkPlugin.contribute(previous: NetworkSessionLog(summary: summary, data: line), to: &report)
            NetworkPlugin.contribute(previous: nil, to: &empty)

            let file = try #require(report.files.first)
            let archive = try HTTPArchive.read(file.data)
            #expect(file.name == "network-previous.har")
            #expect(file.kind == .har)
            #expect(archive.log.entries.map(\.request.url) == ["https://api.example.com/v1/orders"])
            #expect(!(String(bytes: file.data, encoding: .utf8) ?? "").contains("report-secret"))
            #expect(empty.files.isEmpty)
        }
    }
#endif
