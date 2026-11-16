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

        @Test("Without an uploader a ready report has no Send Report button")
        func noUploaderHidesSend() throws {
            let url = URL(fileURLWithPath: "/tmp/Shop-Report-2027-01-15T08-00-00Z.zip")
            let sut = DrawerReportResult(state: .ready(url), send: nil) {}

            #expect(throws: (any Error).self) {
                try sut.inspect().find(ViewType.Button.self) { try $0.accessibilityLabel().string() == "Send the report" }
            }
        }

        @Test("With an uploader a ready report has a Send Report button that sends its zip")
        func sendSendsTheZip() throws {
            let url = URL(fileURLWithPath: "/tmp/Shop-Report-2027-01-15T08-00-00Z.zip")
            var sent: [URL] = []
            let sut = DrawerReportResult(state: .ready(url), send: { sent.append($0) }, dismiss: {})

            try sut.inspect().find(ViewType.Button.self) { try $0.accessibilityLabel().string() == "Send the report" }.tap()

            #expect(sent == [url])
        }

        @Test("While the report is sent it shows the fraction sent, and can't be dismissed or sent again")
        func uploadingShowsProgress() throws {
            let url = URL(fileURLWithPath: "/tmp/Shop-Report-2027-01-15T08-00-00Z.zip")
            let sut = DrawerReportResult(state: .uploading(url, progress: 0.4), send: { _ in }, dismiss: {})
            let expectedFraction = 0.4

            let title = try sut.inspect().find(text: "Sending report…")
            let fraction = try sut.inspect().find(ViewType.ProgressView.self).fractionCompleted()

            #expect(try title.string() == "Sending report…")
            #expect(fraction == expectedFraction)
            #expect(throws: (any Error).self) {
                try sut.inspect().find(ViewType.Button.self) { try $0.accessibilityLabel().string() == "Dismiss the report result" }
            }
            #expect(throws: (any Error).self) {
                try sut.inspect().find(ViewType.Button.self) { try $0.accessibilityLabel().string() == "Send the report" }
            }
        }

        @Test("A failed upload shows the uploader's message and a Retry button that sends the same zip")
        func uploadFailedRetries() throws {
            let url = URL(fileURLWithPath: "/tmp/Shop-Report-2027-01-15T08-00-00Z.zip")
            var sent: [URL] = []
            let sut = DrawerReportResult(
                state: .uploadFailed(url, reason: "The server is down for maintenance."),
                send: { sent.append($0) },
                dismiss: {}
            )

            let title = try sut.inspect().find(text: "Couldn't send the report")
            let reason = try sut.inspect().find(text: "The server is down for maintenance.")
            try sut.inspect().find(ViewType.Button.self) { try $0.accessibilityLabel().string() == "Retry sending the report" }.tap()

            #expect(try title.string() == "Couldn't send the report")
            #expect(try reason.string() == "The server is down for maintenance.")
            #expect(sent == [url])
        }

        @Test("A sent report says so and can't be sent again")
        func sentSaysSo() throws {
            let url = URL(fileURLWithPath: "/tmp/Shop-Report-2027-01-15T08-00-00Z.zip")
            let sut = DrawerReportResult(state: .sent(url), send: { _ in }, dismiss: {})

            let title = try sut.inspect().find(text: "Report sent")

            #expect(try title.string() == "Report sent")
            #expect(throws: (any Error).self) {
                try sut.inspect().find(ViewType.Button.self) { try $0.accessibilityLabel().string() == "Send the report" }
            }
            #expect(throws: (any Error).self) {
                try sut.inspect().find(ViewType.Button.self) { try $0.accessibilityLabel().string() == "Retry sending the report" }
            }
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
