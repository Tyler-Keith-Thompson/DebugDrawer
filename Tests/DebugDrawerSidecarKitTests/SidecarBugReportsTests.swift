#if DEBUG && os(macOS)
    import AppKit
    import DebugDrawer
    @testable import DebugDrawerReceiver
    @testable import DebugDrawerSidecarKit
    import Foundation
    import Testing
    import ViewInspector

    // A bug report from the production app's receiver to the sidecar's report: the app takes one as
    // its own trigger fires in a session, the kit lists the app and shows the report through its
    // Bug Reports plugin over the store, the employee annotates it, and Create Report puts the
    // screenshot, the note with the annotation and the state in the zip the sidecar's uploader would
    // send, while the app records the export. Each wait is for the file or snapshot that step should
    // produce, never for time.
    @MainActor
    @Suite(.timeLimit(.minutes(1)), .serialized)
    struct SidecarBugReportsTests {
        /// A 2 by 2 PNG, standing in for the app's window.
        static let png: Data = {
            let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            )
            // The parameters describe a valid 2 by 2 RGBA bitmap, which always encodes as PNG.
            return bitmap!.representation(using: .png, properties: [:])!
        }()

        @Test("A report the app takes shows in the kit, and Create Report holds its screenshot, note, annotation and redacted state; export recorded")
        func reportReachesTheSidecarsReport() async throws {
            let store = FileManager.default.temporaryDirectory
                .appending(path: "SidecarBugReportsTests-\(UUID().uuidString)")
                .appending(path: "DebugDrawer")
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let reports = DebugDrawerBugReports(
                sessions: sessions, diagnostics: nil, redaction: .standard, limits: .standard,
                state: { ["screen": "checkout", "email": "jane@example.com"] },
                screenshot: { _ in .png(Self.png) },
                now: { Date() }
            )
            let receiver = DebugDrawerReceiver(directory: store, sessions: sessions)
            receiver.identity = AppPresence.Identity(bundleIdentifier: "com.example.shop", displayName: "Shop", version: "2.4", build: "881")
            receiver.enable(.bugReports(reports))
            try receiver.start()
            defer { receiver.stop() }
            sessions.perform(.open(duration: 60))
            let snapshotFile = AppGroupStoreLayout(directory: receiver.appDirectory).snapshotFile(for: DebugDrawerBugReports.pluginID)
            let watcher = try #require(DirectoryWatcher(directory: snapshotFile.deletingLastPathComponent()))
            defer { watcher.cancel() }
            func storedReportCount() -> Int? {
                guard let data = try? Data(contentsOf: snapshotFile), let document = StoreDocument.decoded(from: data) else { return nil }
                return try? JSONDecoder().decode(DebugDrawerBugReports.Snapshot.self, from: document.message.payload).reports.count
            }
            reports.trigger(note: "Checkout froze")
            if storedReportCount() != 1 {
                for await _ in watcher.changes where storedReportCount() == 1 {
                    break
                }
            }
            let listed = try #require(DebugDrawerSidecarAppList(storeDirectory: store).apps.first)
            let sut = try DebugDrawerSidecarConnection(app: listed)
            defer { sut.close() }
            let directory = store.deletingLastPathComponent().appending(path: "Reports")

            let hosted = try await sut.host(.bugReports)
            // Bug Reports keeps its type's default ID, unlike its model's: hosting it again
            // still finds the one shown (DD-269).
            _ = try await sut.host(.bugReports)
            try hosted.body.inspect().find(ViewType.TextField.self).setInput("Tapped Pay twice")
            let archive = try sut.createReport(in: directory)

            let unzipped = directory.appending(path: "unzipped")
            let unzip = Process()
            unzip.executableURL = URL(filePath: "/usr/bin/ditto")
            unzip.arguments = ["-x", "-k", archive.path, unzipped.path]
            try unzip.run()
            unzip.waitUntilExit()
            let folder = try #require(try FileManager.default.contentsOfDirectory(at: unzipped, includingPropertiesForKeys: nil).first)
            let screenshot = try Data(contentsOf: folder.appending(path: "Bug Reports/screenshot.png"))
            let note = try String(contentsOf: folder.appending(path: "Bug Reports/note.txt"), encoding: .utf8)
            let state = try String(contentsOf: folder.appending(path: "Bug Reports/state.json"), encoding: .utf8)
            for await snapshot in reports.$snapshot.values where !snapshot.exports.isEmpty {
                break
            }
            #expect(sut.hosted.map(\.title) == ["Bug Reports"])
            #expect(throws: Never.self) { try hosted.body.inspect().find(text: "Checkout froze") }
            #expect(screenshot == Self.png)
            #expect(note.contains("Note: Checkout froze"))
            #expect(note.contains("Annotation: Tapped Pay twice"))
            #expect(state == #"{"email":"[REDACTED]","screen":"checkout"}"#)
            #expect(reports.snapshot.exports.map(\.reportID) == reports.snapshot.reports.map(\.id))
        }

        @Test("With no report taken, the kit's Bug Reports says so and adds nothing to the report")
        func noReport() throws {
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let reports = DebugDrawerBugReports(sessions: sessions)
            let review = BugReportReview()
            let sut = BugReportsPlugin(transport: .direct(to: reports), review: review)
            var report = DebugDrawerReport()

            sut.contribute(to: &report, redaction: DebugDrawerRedaction())

            #expect(report.files.isEmpty)
            #expect(throws: Never.self) { try sut.body.inspect().find(text: "No Bug Reports") }
        }

        @Test("The report picked is the one Create Report takes; the newest when none was picked")
        func pickedReport() {
            let older = DebugDrawerBugReports.Report(
                id: UUID(), date: Date(timeIntervalSince1970: 1), note: "older", screenshot: .unavailable, logs: .notCapturing, state: nil
            )
            let newer = DebugDrawerBugReports.Report(
                id: UUID(), date: Date(timeIntervalSince1970: 2), note: "newer", screenshot: .unavailable, logs: .notCapturing, state: nil
            )
            let sut = BugReportReview()
            let byDefault = sut.report(of: [older, newer])

            sut.picked = older.id
            let actual = sut.report(of: [older, newer])

            #expect(byDefault == newer)
            #expect(actual == older)
        }

        @Test("The shipped Bug Reports plugin is served under the capability's ID")
        func shippedPlugin() {
            let sut = DebugDrawerSidecarPlugin.bugReports

            #expect([sut.id, sut.title, sut.icon] == [DebugDrawerBugReports.pluginID, "Bug Reports", "ladybug"])
        }
    }
#endif
