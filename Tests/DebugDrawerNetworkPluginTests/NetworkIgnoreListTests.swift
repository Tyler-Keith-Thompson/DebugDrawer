#if DEBUG
    @testable import DebugDrawerNetworkPlugin
    import Foundation
    import Testing

    @MainActor
    @Suite
    struct NetworkIgnoreListTests {
        @Test("Adding a host to the ignore list hides its requests, and its subdomains', from filteredEntries; other hosts stay")
        func ignoringHidesHostAndSubdomains() throws {
            let sut = NetworkStore(ignoreStorage: FakeNetworkIgnoreListStorage())
            for host in ["api.example.com", "analytics.example.net", "cdn.analytics.example.net", "badanalytics.example.net"] {
                sut.recordStart(NetworkEntry(
                    timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000), method: "GET", url: "https://\(host)/v1/a",
                    host: host, path: "/v1/a", requestHeaders: [:], requestBody: nil, statusCode: 200, isComplete: true
                ))
            }
            let domain = try NetworkIgnoredDomain(parsing: "analytics.example.net")

            sut.ignore(domain)

            let actual = sut.filteredEntries.map(\.host)
            #expect(actual == ["badanalytics.example.net", "api.example.com"])
            #expect(sut.entries.count == 4)
        }

        @Test("The ignore list survives creating a new NetworkStore over the same storage")
        func persistsAcrossStores() throws {
            let storage = FakeNetworkIgnoreListStorage()
            let first = NetworkStore(ignoreStorage: storage)
            first.ignore(try NetworkIgnoredDomain(parsing: "analytics.example.net"))
            first.ignore(try NetworkIgnoredDomain(parsing: "cdn.example.com"))
            first.stopIgnoring(try NetworkIgnoredDomain(parsing: "cdn.example.com"))
            first.ignore(try NetworkIgnoredDomain(parsing: "10.0.0.1"))
            let sut = NetworkStore(ignoreStorage: storage)

            sut.loadIgnoreList()

            let actual = sut.ignoredDomains.map(\.name)
            #expect(actual == ["analytics.example.net", "10.0.0.1"])
            #expect(sut.ignoreIssue == nil)
        }

        @Test("The saved file is version 1 JSON listing the domains in order")
        func fileFormat() throws {
            let storage = FakeNetworkIgnoreListStorage()
            let sut = NetworkStore(ignoreStorage: storage)

            sut.ignore(try NetworkIgnoredDomain(parsing: "b.example.com"))
            sut.ignore(try NetworkIgnoredDomain(parsing: "a.example.com"))

            let saved = try #require(storage.savedFile)
            let actual = try JSONDecoder().decode(NetworkIgnoreListFile.self, from: saved)
            #expect(actual == NetworkIgnoreListFile(version: 1, domains: ["b.example.com", "a.example.com"]))
        }

        @Test("Ignoring a domain the list holds already changes and writes nothing")
        func ignoringTwiceIsOnce() throws {
            let storage = FakeNetworkIgnoreListStorage()
            let sut = NetworkStore(ignoreStorage: storage)
            let domain = try NetworkIgnoredDomain(parsing: "example.com")
            sut.ignore(domain)

            sut.ignore(try NetworkIgnoredDomain(parsing: "EXAMPLE.com."))

            #expect(sut.ignoredDomains == [domain])
            #expect(storage.writeCount == 1)
        }

        @Test("The app's seeds join the saved list at the end, once, and loading writes nothing")
        func seedsJoinWithoutWriting() throws {
            let saved = NetworkIgnoreListFile.encode([try NetworkIgnoredDomain(parsing: "saved.example.com")])
            let storage = FakeNetworkIgnoreListStorage(file: saved)
            let sut = NetworkStore(ignoreStorage: storage)
            let seeds = try ["saved.example.com", "seed.example.com"].map { try NetworkIgnoredDomain(parsing: $0) }

            sut.loadIgnoreList(adding: seeds)

            #expect(sut.ignoredDomains.map(\.name) == ["saved.example.com", "seed.example.com"])
            #expect(storage.writeCount == 0)
        }

        @Test("A saved file that isn't the format loads an empty list and says it wasn't loaded")
        func unreadableFile() {
            let sut = NetworkStore(ignoreStorage: FakeNetworkIgnoreListStorage(file: Data("not json".utf8)))

            sut.loadIgnoreList()

            #expect(sut.ignoredDomains.isEmpty)
            #expect(sut.ignoreIssue == .unreadable)
        }

        @Test("A saved file of a later format loads an empty list and names the version")
        func laterVersion() {
            let sut = NetworkStore(ignoreStorage: FakeNetworkIgnoreListStorage(file: Data(#"{"version":2,"domains":["example.com"]}"#.utf8)))

            sut.loadIgnoreList()

            #expect(sut.ignoredDomains.isEmpty)
            #expect(sut.ignoreIssue == .unsupportedVersion(2))
        }

        @Test("A hand-edited entry that isn't a host is dropped; the rest load")
        func dropsMalformedEntries() {
            let file = Data(#"{"version":1,"domains":["good.example.com","not a host","*.cdn.example.com","10.0.0.1"]}"#.utf8)
            let sut = NetworkStore(ignoreStorage: FakeNetworkIgnoreListStorage(file: file))

            sut.loadIgnoreList()

            #expect(sut.ignoredDomains.map(\.name) == ["good.example.com", "10.0.0.1"])
            #expect(sut.ignoreIssue == nil)
        }

        @Test("A change that can't be saved still applies, says so, and the next save that works clears it")
        func writeFailure() throws {
            let storage = FakeNetworkIgnoreListStorage()
            storage.failsWriting = true
            let sut = NetworkStore(ignoreStorage: storage)

            sut.ignore(try NetworkIgnoredDomain(parsing: "example.com"))
            let issueWhileFailing = sut.ignoreIssue
            storage.failsWriting = false
            sut.ignore(try NetworkIgnoredDomain(parsing: "example.net"))

            #expect(issueWhileFailing == .notSaved)
            #expect(sut.ignoreIssue == nil)
            #expect(sut.ignoredDomains.map(\.name) == ["example.com", "example.net"])
        }

        @Test("The file on disk is ignored.json in the folder given, read back as written")
        func diskStorage() throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: "NetworkIgnoreListTests-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: directory) }
            let sut = _NetworkIgnoreListStorage(directory: directory)
            let before = try sut.readIgnoreList()
            let data = Data(#"{"version":1,"domains":[]}"#.utf8)

            try sut.writeIgnoreList(data)

            #expect(before == nil)
            #expect(try sut.readIgnoreList() == data)
            #expect(FileManager.default.fileExists(atPath: directory.appending(path: "ignored.json").path(percentEncoded: false)))
        }

        @Test("Ignored WebSocket connections are hidden too, by their URL's host")
        func webSocketsIgnored() throws {
            let sut = NetworkStore(ignoreStorage: FakeNetworkIgnoreListStorage())
            let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
            sut.showWebSockets([
                NetworkWebSocketConnection(url: "wss://chat.example.com/room", opened: start),
                NetworkWebSocketConnection(url: "wss://live.tracking.example.net/v1", opened: start)
            ])

            sut.ignore(try NetworkIgnoredDomain(parsing: "tracking.example.net"))

            #expect(sut.filteredWebSockets.map(\.url) == ["wss://chat.example.com/room"])
            #expect(sut.ignoredCount == 1)
        }

        @Test("The hint counts what the filters pass that the list hides, and Show lists them again, still counted")
        func hiddenCountAndShow() throws {
            let sut = NetworkStore(ignoreStorage: FakeNetworkIgnoreListStorage())
            let rows: [(host: String, status: Int)] = [
                ("analytics.example.net", 200), ("analytics.example.net", 200), ("analytics.example.net", 500), ("api.example.com", 200)
            ]
            for row in rows {
                sut.recordStart(NetworkEntry(
                    timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000), method: "POST", url: "https://\(row.host)/e",
                    host: row.host, path: "/e", requestHeaders: [:], requestBody: nil, statusCode: row.status, isComplete: true
                ))
            }
            sut.ignore(try NetworkIgnoredDomain(parsing: "example.net"))
            let hiddenAll = sut.ignoredCount
            let shownAll = sut.filteredEntries.count
            sut.filterStatus = .serverError
            let hiddenServerErrors = sut.ignoredCount
            sut.filterStatus = .all

            sut.showsIgnored = true

            #expect(hiddenAll == 3)
            #expect(shownAll == 1)
            #expect(hiddenServerErrors == 1)
            #expect(sut.filteredEntries.count == 4)
            #expect(sut.ignoredCount == 3)
        }

        @Test("With nothing ignored, nothing is counted")
        func emptyListCountsNothing() {
            let sut = NetworkStore(ignoreStorage: FakeNetworkIgnoreListStorage())
            sut.recordStart(NetworkEntry(
                timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000), method: "GET", url: "https://example.com/",
                host: "example.com", path: "/", requestHeaders: [:], requestBody: nil, isComplete: false
            ))

            let actual = sut.ignoredCount

            #expect(actual == 0)
            #expect(sut.filteredEntries.count == 1)
        }

        @Test("The pure filter hides ignored hosts from any list of requests: captured, an earlier session's or an imported file's")
        func pureFilterAppliesToAnySource() throws {
            let entries = ["imported.example.com", "ads.example.org", "x.ads.example.org"].map { host in
                NetworkEntry(
                    timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000), method: "GET", url: "https://\(host)/",
                    host: host, path: "/", requestHeaders: [:], requestBody: nil, statusCode: 200, isComplete: true
                )
            }
            let ignored = [try NetworkIgnoredDomain(parsing: "ads.example.org")]

            let actual = NetworkStore.entries(entries, matching: .all, text: "", ignoring: ignored).map(\.host)

            #expect(actual == ["imported.example.com"])
        }
    }
#endif
