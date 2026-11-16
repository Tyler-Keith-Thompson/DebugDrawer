#if DEBUG
    @testable import DebugDrawerCrashReportsPlugin
    import Foundation
    import Testing

    @MainActor
    @Suite
    struct CrashReportStoreTests {
        @Test("The crash file the last run left becomes an unseen report, kept on disk, and the file is deleted")
        func collect() throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            var counts: [Int] = []
            let sut = CrashReportStore(directory: directory) { counts.append($0) }
            let text = "DebugDrawer crash report 1\ntime 1763290000\nsignal 11\nframes\n0 Example 0x1\nend\n"
            try Data(text.utf8).write(to: sut.crashFile)
            let id = UUID()

            let actual = try #require(sut.collectCrashFile(id: id))

            #expect(actual.title == "SIGSEGV")
            #expect(sut.reports == [actual])
            #expect(sut.unseenCount == 1)
            #expect(counts == [1])
            #expect(!FileManager.default.fileExists(atPath: sut.crashFile.path(percentEncoded: false)))
            #expect(CrashReportStore(directory: directory).reports == [actual])
        }

        @Test("No crash file collects nothing")
        func collectNothing() {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let sut = CrashReportStore(directory: directory)

            let actual = sut.collectCrashFile()

            #expect(actual == nil)
            #expect(sut.reports.isEmpty)
        }

        @Test("A crash file that isn't one is deleted and kept as no report")
        func collectGarbage() throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let sut = CrashReportStore(directory: directory)
            try Data("garbage".utf8).write(to: sut.crashFile)

            let actual = sut.collectCrashFile()

            #expect(actual == nil)
            #expect(sut.reports.isEmpty)
            #expect(!FileManager.default.fileExists(atPath: sut.crashFile.path(percentEncoded: false)))
        }

        @Test("Reports are listed newest first, and only the newest ten are kept, on disk too")
        func keepsNewest() {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let sut = CrashReportStore(directory: directory)
            let reports = (0 ..< 12).map { second in
                CrashReport(
                    id: UUID(), date: Date(timeIntervalSince1970: TimeInterval(second)), title: "SIGABRT", reason: nil,
                    appVersion: nil, frames: [], source: .captured, isSeen: false
                )
            }
            let expected = Array(reports.reversed().prefix(10))

            for report in reports.shuffled() {
                sut.add(report)
            }

            #expect(sut.reports == expected)
            #expect(CrashReportStore(directory: directory).reports == expected)
            let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))) ?? []
            #expect(files.count == 10)
        }

        @Test("Opening a report marks it seen, which lowers the badge and lasts across launches")
        func markSeen() {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            var counts: [Int] = []
            let sut = CrashReportStore(directory: directory) { counts.append($0) }
            let first = CrashReport(
                id: UUID(), date: Date(timeIntervalSince1970: 1), title: "SIGSEGV", reason: nil, appVersion: nil,
                frames: [], source: .captured, isSeen: false
            )
            let second = CrashReport(
                id: UUID(), date: Date(timeIntervalSince1970: 2), title: "SIGTRAP", reason: nil, appVersion: nil,
                frames: [], source: .captured, isSeen: false
            )
            sut.add(first)
            sut.add(second)

            sut.markSeen(first.id)

            #expect(sut.unseenCount == 1)
            #expect(counts == [1, 2, 1])
            #expect(CrashReportStore(directory: directory).reports.map(\.isSeen) == [false, true])
        }

        @Test("Mark All Seen clears the badge")
        func markAllSeen() {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            var counts: [Int] = []
            let sut = CrashReportStore(directory: directory) { counts.append($0) }
            for second in 1 ... 2 {
                sut.add(CrashReport(
                    id: UUID(), date: Date(timeIntervalSince1970: TimeInterval(second)), title: "SIGSEGV", reason: nil,
                    appVersion: nil, frames: [], source: .captured, isSeen: false
                ))
            }

            sut.markAllSeen()

            #expect(sut.unseenCount == 0)
            #expect(counts.last == 0)
            #expect(CrashReportStore(directory: directory).unseenCount == 0)
        }

        @Test("Deleting a report removes it, from disk too, and Delete All removes the rest")
        func delete() {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            var counts: [Int] = []
            let sut = CrashReportStore(directory: directory) { counts.append($0) }
            let reports = (1 ... 3).map { second in
                CrashReport(
                    id: UUID(), date: Date(timeIntervalSince1970: TimeInterval(second)), title: "SIGSEGV", reason: nil,
                    appVersion: nil, frames: [], source: .captured, isSeen: false
                )
            }
            for report in reports {
                sut.add(report)
            }

            sut.delete(reports[1].id)

            #expect(sut.reports.map(\.id) == [reports[2].id, reports[0].id])
            #expect(CrashReportStore(directory: directory).reports.map(\.id) == [reports[2].id, reports[0].id])

            sut.deleteAll()

            #expect(sut.reports.isEmpty)
            #expect(CrashReportStore(directory: directory).reports.isEmpty)
            #expect(counts == [1, 2, 3, 2, 0])
        }

        @Test("MetricKit's crash diagnostics become MetricKit reports; one that isn't a diagnostic is dropped")
        func receive() {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            var counts: [Int] = []
            let sut = CrashReportStore(directory: directory) { counts.append($0) }
            let date = Date(timeIntervalSince1970: 1_763_290_000)
            let diagnostics = [
                CrashDiagnostic(json: Data(#"{ "diagnosticMetaData": { "signal": 6 } }"#.utf8), date: date),
                CrashDiagnostic(json: Data("not json".utf8), date: date)
            ]

            sut.receive(diagnostics)

            #expect(sut.reports.map(\.title) == ["SIGABRT"])
            #expect(sut.reports.map(\.source) == [.metricKit])
            #expect(counts == [1])
        }

        @Test("A file in the directory that isn't a report is skipped on load")
        func loadSkipsGarbage() throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("{}".utf8).write(to: directory.appending(path: "\(UUID().uuidString).json"))

            let sut = CrashReportStore(directory: directory)

            #expect(sut.reports.isEmpty)
        }
    }
#endif
