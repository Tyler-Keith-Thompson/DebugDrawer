// ViewInspector is linked on Apple platforms only, and the views are tested on the Mac.
#if os(macOS)
    @testable import DebugDrawer
    @testable import DebugDrawerCrashReportsPlugin
    import Foundation
    import SwiftUI
    import Testing
    import ViewInspector

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct CrashReportsViewTests {
        @Test("With no reports the plugin says where one will appear, and offers no buttons")
        func empty() throws {
            let sut = CrashReportsView(
                reports: [], expanded: .constant(nil), onOpen: { _ in }, onDelete: { _ in }, onMarkAllSeen: {}, onDeleteAll: {}
            )
            let expected = "No crash reports. After a crash, its report appears here on the next launch."

            let actual = try sut.inspect().find(text: expected).string()

            #expect(actual == expected)
            #expect(throws: (any Error).self) { try sut.inspect().find(button: "Delete All") }
        }

        @Test("Tapping a report opens it and reports it opened; tapping it again closes it")
        func toggle() throws {
            let report = CrashReport(
                id: UUID(), date: Date(timeIntervalSince1970: 1_763_290_000), title: "SIGSEGV", reason: "Segmentation fault",
                appVersion: "1.0 (1)", frames: ["0 Example 0x1"], source: .captured, isSeen: false
            )
            var expanded: CrashReport.ID?
            var opened: [CrashReport.ID] = []
            let sut = CrashReportsView(
                reports: [report],
                expanded: Binding(get: { expanded }, set: { expanded = $0 }),
                onOpen: { opened.append($0) }, onDelete: { _ in }, onMarkAllSeen: {}, onDeleteAll: {}
            )

            try sut.inspect().find(button: "SIGSEGV").tap()

            #expect(expanded == report.id)
            #expect(opened == [report.id])

            try sut.inspect().find(button: "SIGSEGV").tap()

            #expect(expanded == nil)
            #expect(opened == [report.id])
        }

        @Test("An open report shows each frame of its stack trace, symbol and image, and a button that copies the report")
        func expandedShowsFrames() throws {
            let report = CrashReport(
                id: UUID(), date: Date(timeIntervalSince1970: 1_763_290_000), title: "SIGTRAP", reason: nil,
                appVersion: nil, frames: ["0 Example 0x1 crash + 4", "1 Example 0x2 main + 8"], source: .captured, isSeen: true
            )
            let sut = CrashReportsView(
                reports: [report], expanded: .constant(report.id), onOpen: { _ in }, onDelete: { _ in }, onMarkAllSeen: {}, onDeleteAll: {}
            )
            let expected = ["crash", "main", "Example"]

            let actual = try [
                sut.inspect().find(text: "crash").string(),
                sut.inspect().find(text: "main").string(),
                sut.inspect().find(text: "Example").string()
            ]

            #expect(actual == expected)
            #expect(try sut.inspect().find(button: "Copy Report").labelView().text().string() == "Copy Report")
        }

        @Test("A closed report shows no stack trace")
        func collapsedHidesFrames() throws {
            let report = CrashReport(
                id: UUID(), date: Date(timeIntervalSince1970: 1_763_290_000), title: "SIGTRAP", reason: nil,
                appVersion: nil, frames: ["0 Example 0x1"], source: .captured, isSeen: true
            )
            let sut = CrashReportsView(
                reports: [report], expanded: .constant(nil), onOpen: { _ in }, onDelete: { _ in }, onMarkAllSeen: {}, onDeleteAll: {}
            )

            #expect(throws: (any Error).self) { try sut.inspect().find(text: "0 Example 0x1") }
        }

        @Test("An unopened report has an unread dot; an opened one hasn't")
        func newTag() throws {
            let unseen = CrashReport(
                id: UUID(), date: Date(timeIntervalSince1970: 2), title: "SIGSEGV", reason: nil, appVersion: nil,
                frames: [], source: .captured, isSeen: false
            )
            let seen = CrashReport(
                id: UUID(), date: Date(timeIntervalSince1970: 1), title: "SIGBUS", reason: nil, appVersion: nil,
                frames: [], source: .captured, isSeen: true
            )
            let sut = CrashReportsView(
                reports: [unseen, seen], expanded: .constant(nil), onOpen: { _ in }, onDelete: { _ in }, onMarkAllSeen: {}, onDeleteAll: {}
            )

            let actual = try sut.inspect().findAll(DebugDrawerUnreadDot.self)

            #expect(actual.count == 1)
            #expect(try actual.first?.accessibilityLabel().string() == "New report")
        }

        @Test("An open report's Delete button deletes that report")
        func deleteOne() throws {
            let report = CrashReport(
                id: UUID(), date: Date(timeIntervalSince1970: 1), title: "SIGSEGV", reason: nil, appVersion: nil,
                frames: [], source: .captured, isSeen: false
            )
            var deleted: [CrashReport.ID] = []
            let sut = CrashReportsView(
                reports: [report], expanded: .constant(report.id),
                onOpen: { _ in }, onDelete: { deleted.append($0) }, onMarkAllSeen: {}, onDeleteAll: {}
            )

            try sut.inspect().find(ViewType.Button.self, where: { try $0.accessibilityLabel().string() == "Delete report SIGSEGV" }).tap()

            #expect(deleted == [report.id])
        }

        @Test("Delete All and Mark All Seen call their actions")
        func buttons() throws {
            let report = CrashReport(
                id: UUID(), date: Date(timeIntervalSince1970: 1), title: "SIGSEGV", reason: nil, appVersion: nil,
                frames: [], source: .captured, isSeen: false
            )
            var calls: [String] = []
            let sut = CrashReportsView(
                reports: [report], expanded: .constant(nil), onOpen: { _ in }, onDelete: { _ in },
                onMarkAllSeen: { calls.append("seen") }, onDeleteAll: { calls.append("delete") }
            )

            try sut.inspect().find(button: "Mark All Seen").tap()
            try sut.inspect().find(button: "Delete All").tap()

            #expect(calls == ["seen", "delete"])
        }

        @Test("Mark All Seen is disabled once every report is seen")
        func markAllSeenDisabled() throws {
            let report = CrashReport(
                id: UUID(), date: Date(timeIntervalSince1970: 1), title: "SIGSEGV", reason: nil, appVersion: nil,
                frames: [], source: .captured, isSeen: true
            )
            let sut = CrashReportsView(
                reports: [report], expanded: .constant(nil), onOpen: { _ in }, onDelete: { _ in }, onMarkAllSeen: {}, onDeleteAll: {}
            )

            let actual = try sut.inspect().find(button: "Mark All Seen").isDisabled()

            #expect(actual)
        }

        @Test("Opening a report in the plugin marks it seen in the store, which clears the badge")
        func pluginMarksSeen() throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            var counts: [Int] = []
            let store = CrashReportStore(directory: directory) { counts.append($0) }
            store.add(CrashReport(
                id: UUID(), date: Date(timeIntervalSince1970: 1), title: "SIGSEGV", reason: nil, appVersion: nil,
                frames: [], source: .captured, isSeen: false
            ))
            let sut = CrashReportsPluginView(store: store)

            try sut.inspect().find(button: "SIGSEGV").tap()

            #expect(store.unseenCount == 0)
            #expect(counts == [1, 0])
        }

        @Test("The summary reads the date in the view's locale and time zone, with the version and source")
        func facts() throws {
            let report = CrashReport(
                id: UUID(), date: Date(timeIntervalSince1970: 1_763_290_000), title: "SIGSEGV", reason: nil,
                appVersion: "1.2 (34)", frames: [], source: .metricKit, isSeen: true
            )
            let sut = CrashReportsView(
                reports: [report], expanded: .constant(nil), onOpen: { _ in }, onDelete: { _ in }, onMarkAllSeen: {}, onDeleteAll: {}
            )
            .environment(\.locale, Locale(identifier: "en_US"))
            .environment(\.timeZone, try #require(TimeZone(identifier: "UTC")))
            let expected = "Nov 16, 2025 at 10:46\u{202F}AM · 1.2 (34) · MetricKit"

            let actual = try sut.inspect().find(ViewType.Text.self, where: { try $0.string().hasSuffix("MetricKit") }).string()

            #expect(actual == expected)
        }

        @Test("Frames in the app's executable are its own code, and the first of them is selected")
        func ownCode() throws {
            let report = CrashReport(
                id: UUID(), date: Date(timeIntervalSince1970: 1), title: "SIGTRAP", reason: nil, appVersion: nil,
                frames: [
                    "0   libswiftCore.dylib   0x000000018f2b1a40 $ss17_assertionFailureV + 172",
                    "1   Example              0x0000000100004a1c $s7Example5crashyyF + 48",
                    "2   Example              0x0000000100004b00 main + 8"
                ],
                source: .captured, isSeen: true
            )
            let sut = CrashReportsView(
                reports: [report], expanded: .constant(report.id), ownImage: "Example",
                onOpen: { _ in }, onDelete: { _ in }, onMarkAllSeen: {}, onDeleteAll: {}
            )
            let expectedOwn = [false, true, true]
            let expectedSelected = [false, true, false]
            let expectedImages = ["libswiftCore.dylib", "Example", "Example"]

            let rows = try sut.inspect().findAll(DebugDrawerStackFrameRow.self).map { try $0.actualView() }

            #expect(rows.map(\.isOwnCode) == expectedOwn)
            #expect(rows.map(\.isSelected) == expectedSelected)
            #expect(rows.map(\.image) == expectedImages)
        }

        @Test("The header counts the reports with an error glyph, following the store, and shows nothing without one")
        func headerAccessory() throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let store = CrashReportStore(directory: directory)
            let sut = CrashReportsPlugin(store: store, ownImage: "Example")
            let expected = "1 error"

            #expect(throws: (any Error).self) { try sut.headerAccessory.inspect().find(DebugDrawerIssueCount.self) }
            store.add(CrashReport(
                id: UUID(), date: Date(timeIntervalSince1970: 1), title: "SIGSEGV", reason: nil, appVersion: nil,
                frames: [], source: .captured, isSeen: false
            ))
            let actual = try sut.headerAccessory.inspect().find(DebugDrawerIssueCount.self).actualView()

            #expect(actual.severity == .error)
            #expect(actual.spokenLabel == expected)
        }
    }
#endif
