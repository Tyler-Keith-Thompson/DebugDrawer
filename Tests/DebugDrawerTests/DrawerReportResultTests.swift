// ViewInspector is linked on Apple platforms only.
#if os(macOS)
    @testable import DebugDrawer
    import Foundation
    import SwiftUI
    import Testing
    import ViewInspector

    @MainActor
    @Suite("Report result")
    struct DrawerReportResultTests {
        @Test("A ready report shows that it's ready and the zip's file name")
        func readyShowsTheFileName() throws {
            let url = URL(fileURLWithPath: "/tmp/Shop-Report-2027-01-15T08-00-00Z.zip")
            let sut = DrawerReportResult(state: .ready(url)) {}

            let title = try sut.inspect().find(text: "Report ready")
            let name = try sut.inspect().find(text: "Shop-Report-2027-01-15T08-00-00Z.zip")

            #expect(try title.string() == "Report ready")
            #expect(try name.string() == "Shop-Report-2027-01-15T08-00-00Z.zip")
        }

        @Test("A failed report shows why")
        func failedShowsTheReason() throws {
            let sut = DrawerReportResult(state: .failed("The report couldn't be written.")) {}

            let actual = try sut.inspect().find(text: "The report couldn't be written.")

            #expect(try actual.string() == "The report couldn't be written.")
            #expect(throws: (any Error).self) { try sut.inspect().find(text: "Report ready") }
        }

        @Test("The dismiss button dismisses the result")
        func dismissCallsBack() throws {
            var dismissed = 0
            let sut = DrawerReportResult(state: .failed("No space")) { dismissed += 1 }

            try sut.inspect().find(ViewType.Button.self) { try $0.accessibilityLabel().string() == "Dismiss the report result" }.tap()

            #expect(dismissed == 1)
        }

        @Test("While the report is written there is no dismiss button")
        func creatingCantBeDismissed() throws {
            let sut = DrawerReportResult(state: .creating) {}

            let progress = try sut.inspect().find(text: "Creating report…")

            #expect(try progress.string() == "Creating report…")
            #expect(throws: (any Error).self) {
                try sut.inspect().find(ViewType.Button.self) { try $0.accessibilityLabel().string() == "Dismiss the report result" }
            }
        }
    }
#endif
