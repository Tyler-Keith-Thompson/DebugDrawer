#if DEBUG
    import DebugDrawer
    @testable import DebugDrawerCrashReportsPlugin
    import Foundation
    import Testing

    @MainActor
    @Suite
    struct CrashReportsPluginTests {
        @Test("The plugin is Crash Reports, in the App category, and adds to bug reports")
        func identity() {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }

            let sut = CrashReportsPlugin(store: CrashReportStore(directory: directory))

            #expect(sut.id == "CrashReportsPlugin")
            #expect(sut.title == "Crash Reports")
            #expect(sut.category == "App")
            #expect(sut.icon == "exclamationmark.octagon")
            #expect(AnyDebugDrawerPlugin(sut).contributesToReport)
        }

        @Test("The drawer's search offers deleting every report, found by \"crash\" too")
        func action() throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let store = CrashReportStore(directory: directory)
            store.add(CrashReport(
                id: UUID(), date: Date(timeIntervalSince1970: 1), title: "SIGSEGV", reason: nil, appVersion: nil,
                frames: [], source: .captured, isSeen: false
            ))
            let sut = CrashReportsPlugin(store: store)

            let actual = try #require(sut.actions.first)
            actual.perform()

            #expect(sut.actions.map(\.title) == ["Delete crash reports"])
            #expect(actual.keywords.contains("crash"))
            #expect(store.reports.isEmpty)
        }

        @Test("The bug report gets each crash as a text file named by its title and date")
        func report() throws {
            let reports = [
                CrashReport(
                    id: UUID(), date: Date(timeIntervalSince1970: 1_763_290_000), title: "SIGSEGV", reason: "Segmentation fault",
                    appVersion: "1.0 (1)", frames: ["0 Example 0x1"], source: .captured, isSeen: false
                ),
                CrashReport(
                    id: UUID(), date: Date(timeIntervalSince1970: 0), title: "NSInvalidArgumentException", reason: nil,
                    appVersion: nil, frames: [], source: .metricKit, isSeen: true
                )
            ]
            let expectedNames = ["SIGSEGV 2025-11-16T10-46-40Z.txt", "NSInvalidArgumentException 1970-01-01T00-00-00Z.txt"]
            let expectedText = "SIGSEGV: Segmentation fault\nDate: 2025-11-16T10:46:40Z\nApp: 1.0 (1)\nSource: Captured\n\n0 Example 0x1\n"
            var actual = DebugDrawerReport()

            CrashReportsPlugin.contribute(reports, to: &actual)

            #expect(actual.files.map(\.name) == expectedNames)
            #expect(actual.files.map(\.kind) == [.text, .text])
            #expect(String(bytes: try #require(actual.files.first).data, encoding: .utf8) == expectedText)
        }

        @Test("No reports add nothing to the bug report")
        func reportEmpty() {
            var actual = DebugDrawerReport()

            CrashReportsPlugin.contribute([], to: &actual)

            #expect(actual.files.isEmpty)
        }

        @Test("The default directory is the app's own folder in Application Support")
        func defaultDirectory() {
            let actual = CrashReports.defaultDirectory

            #expect(actual.lastPathComponent == "DebugDrawer Crash Reports")
            #expect(actual.deletingLastPathComponent().deletingLastPathComponent() == URL.applicationSupportDirectory)
        }
    }
#endif
