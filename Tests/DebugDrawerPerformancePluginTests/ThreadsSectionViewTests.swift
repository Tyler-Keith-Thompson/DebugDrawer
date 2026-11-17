// ViewInspector is linked on Apple platforms only, and the views are tested on the Mac.
#if os(macOS)
    @testable import DebugDrawerPerformancePlugin
    import SwiftUI
    import Testing
    import ViewInspector

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct ThreadsSectionViewTests {
        @Test("Collapsed, the list shows the eight busiest threads in order and counts the rest")
        func collapsed() throws {
            let busy = (1 ... 10).map { ThreadCPU(name: "worker-\($0)", threadID: UInt64($0), cpuUsage: 1 - Double($0) / 20) }
            let idle = (11 ... 13).map { ThreadCPU(name: "idle-\($0)", threadID: UInt64($0), cpuUsage: 0) }
            let sut = ThreadsSection(threads: busy + idle)
            let expectedNames = (1 ... 8).map { "worker-\($0)" }
            let expectedSummary = "5 more threads, 3 idle"

            let rows = try sut.inspect().findAll(ThreadCPURow.self)
            let actualNames = try rows.map { try $0.actualView().thread.name }
            let summary = try sut.inspect().find(text: expectedSummary).string()

            #expect(actualNames == expectedNames)
            #expect(summary == expectedSummary)
            _ = try sut.inspect().find(button: "Show All 13")
        }

        @Test("Each row shows the thread's name and its share of a core as a percentage")
        func row() throws {
            let sut = ThreadCPURow(thread: ThreadCPU(name: "dd54-busy", threadID: 7, cpuUsage: 0.873))
            let expected = ["dd54-busy", "87.3%"]

            let actual = try sut.inspect().findAll(ViewType.Text.self).map { try $0.string() }

            #expect(actual == expected)
        }

        @Test("Show All lists every thread, idle ones too, and Show Busiest folds them again")
        func showAll() async throws {
            let threads = [
                ThreadCPU(name: "busy", threadID: 1, cpuUsage: 0.5),
                ThreadCPU(name: "idle", threadID: 2, cpuUsage: 0)
            ]
            let sut = ThreadsSection(threads: threads)
            var before: [String] = []
            var expanded: [String] = []
            var after: [String] = []

            try await ViewHosting.host(sut) {
                try await sut.inspection.inspect { view in
                    before = try view.findAll(ThreadCPURow.self).map { try $0.actualView().thread.name }
                    try view.find(button: "Show All 2").tap()
                }
                try await sut.inspection.inspect { view in
                    expanded = try view.findAll(ThreadCPURow.self).map { try $0.actualView().thread.name }
                    try view.find(button: "Show Busiest").tap()
                }
                try await sut.inspection.inspect { view in
                    after = try view.findAll(ThreadCPURow.self).map { try $0.actualView().thread.name }
                }
            }

            #expect(before == ["busy"])
            #expect(expanded == ["busy", "idle"])
            #expect(after == ["busy"])
        }

        @Test("With every thread idle, the list says so instead of showing rows")
        func allIdle() throws {
            let threads = (1 ... 3).map { ThreadCPU(name: "idle-\($0)", threadID: UInt64($0), cpuUsage: 0) }
            let sut = ThreadsSection(threads: threads)

            let rows = try sut.inspect().findAll(ThreadCPURow.self)
            let summary = try sut.inspect().find(text: "All 3 threads idle").string()

            #expect(rows.isEmpty)
            #expect(summary == "All 3 threads idle")
        }

        @Test("With every thread shown already, there is no Show All")
        func fewThreads() throws {
            let threads = [ThreadCPU(name: "busy", threadID: 1, cpuUsage: 0.5)]
            let sut = ThreadsSection(threads: threads)

            let actual = try sut.inspect().findAll(ViewType.Button.self)

            #expect(actual.isEmpty)
        }
    }
#endif
