#if DEBUG
    @testable import DebugDrawer
    import Foundation
    import Testing

    /// An uploader that records each archive it's handed, reports the progress steps the test
    /// chose, then waits for the test to open its gate with an outcome.
    actor GatedReportUploader: DebugDrawerReportUploader {
        enum Outcome: Sendable {
            case succeed
            case fail(String)
        }

        struct Refused: LocalizedError {
            let message: String
            var errorDescription: String? { message }
        }

        private let progressSteps: [Double]
        private(set) var archives: [URL] = []
        private var openedOutcomes: [Outcome] = []
        private var waiting: CheckedContinuation<Outcome, Never>?

        init(progressSteps: [Double] = []) {
            self.progressSteps = progressSteps
        }

        func upload(_ archive: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
            archives.append(archive)
            for step in progressSteps {
                progress(step)
            }
            let outcome = await withCheckedContinuation { continuation in
                if openedOutcomes.isEmpty {
                    waiting = continuation
                } else {
                    continuation.resume(returning: openedOutcomes.removeFirst())
                }
            }
            if case let .fail(message) = outcome {
                throw Refused(message: message)
            }
        }

        /// Lets the waiting upload, or the next one, finish with `outcome`.
        func open(_ outcome: Outcome) {
            if let waiting {
                self.waiting = nil
                waiting.resume(returning: outcome)
            } else {
                openedOutcomes.append(outcome)
            }
        }
    }

    @MainActor
    @Suite("Sending reports", .timeLimit(.minutes(1)))
    struct ReportUploadTests {
        @Test("The drawer starts with no uploader, so a report is never sent")
        func noUploaderByDefault() {
            let actual = DebugDrawer.shared.reportUploader

            #expect(actual == nil)
        }

        @Test("Creating a report sends nothing, even with an uploader set; only Send Report does")
        func creatingDoesNotUpload() async throws {
            let uploader = GatedReportUploader()
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let previous = DebugDrawer.shared.reportUploader
            DebugDrawer.shared.reportUploader = uploader

            let zip = try DebugDrawer.shared.createReport(in: directory)

            // Leave the shared drawer as the other suites expect it, within this one main-actor turn.
            DebugDrawer.shared.reportUploader = previous
            defer { try? FileManager.default.removeItem(at: directory) }
            let actual = await uploader.archives
            #expect(FileManager.default.fileExists(atPath: zip.path))
            #expect(actual.isEmpty)
        }

        @Test("Sending shows uploading at 0, then each fraction the uploader reports, then sent")
        func progressThenSent() async throws {
            let archive = URL(fileURLWithPath: "/tmp/Shop-Report.zip")
            let uploader = GatedReportUploader(progressSteps: [0.25, 0.5])
            let (states, continuation) = AsyncStream.makeStream(of: DrawerReportResult.State.self)
            let expectedProgress: [DrawerReportResult.State] = [
                .uploading(archive, progress: 0),
                .uploading(archive, progress: 0.25),
                .uploading(archive, progress: 0.5)
            ]
            let expectedOutcome = DrawerReportResult.State.sent(archive)

            let sending = Task {
                await DrawerReportResult.State.send(archive, with: uploader) { continuation.yield($0) }
                continuation.finish()
            }
            var iterator = states.makeAsyncIterator()
            var progress: [DrawerReportResult.State] = []
            for _ in expectedProgress {
                progress.append(try #require(await iterator.next()))
            }
            await uploader.open(.succeed)
            let outcome = await iterator.next()
            await sending.value

            #expect(progress == expectedProgress)
            #expect(outcome == expectedOutcome)
            #expect(await uploader.archives == [archive])
        }

        @Test("Progress outside 0 to 1 is clamped")
        func progressIsClamped() async throws {
            let archive = URL(fileURLWithPath: "/tmp/Shop-Report.zip")
            let uploader = GatedReportUploader(progressSteps: [-0.5, 1.5])
            let expected: [DrawerReportResult.State] = [
                .uploading(archive, progress: 0),
                .uploading(archive, progress: 0),
                .uploading(archive, progress: 1),
                .sent(archive)
            ]
            await uploader.open(.succeed)
            let (states, continuation) = AsyncStream.makeStream(of: DrawerReportResult.State.self)

            await DrawerReportResult.State.send(archive, with: uploader) { continuation.yield($0) }
            continuation.finish()

            var actual: [DrawerReportResult.State] = []
            for await state in states {
                actual.append(state)
            }
            #expect(actual == expected)
        }

        @Test("A failed upload shows the uploader's message, keeps the archive, and Retry sends the same archive again")
        func failureKeepsTheArchiveAndRetries() async throws {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let archive = directory.appendingPathComponent("Shop-Report.zip")
            try Data("zip".utf8).write(to: archive)
            let uploader = GatedReportUploader()
            let expectedFailure = DrawerReportResult.State.uploadFailed(archive, reason: "The server is down for maintenance.")
            let expectedRetry = DrawerReportResult.State.sent(archive)
            var failure: DrawerReportResult.State?
            var retry: DrawerReportResult.State?
            await uploader.open(.fail("The server is down for maintenance."))
            await uploader.open(.succeed)

            await DrawerReportResult.State.send(archive, with: uploader) { failure = $0 }
            let archiveSurvived = FileManager.default.fileExists(atPath: archive.path)
            await DrawerReportResult.State.send(archive, with: uploader) { retry = $0 }

            #expect(failure == expectedFailure)
            #expect(archiveSurvived)
            #expect(retry == expectedRetry)
            #expect(await uploader.archives == [archive, archive])
        }

        @Test("A report being sent is in progress; a sent one, or one whose upload failed, is not")
        func uploadingIsInProgress() {
            let archive = URL(fileURLWithPath: "/tmp/Shop-Report.zip")

            #expect(DrawerReportResult.State.uploading(archive, progress: 0.5).isInProgress)
            #expect(DrawerReportResult.State.creating.isInProgress)
            #expect(!DrawerReportResult.State.sent(archive).isInProgress)
            #expect(!DrawerReportResult.State.uploadFailed(archive, reason: "No network").isInProgress)
            #expect(!DrawerReportResult.State.ready(archive).isInProgress)
        }
    }
#endif
