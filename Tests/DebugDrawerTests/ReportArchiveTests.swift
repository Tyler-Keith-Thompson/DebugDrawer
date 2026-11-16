// The archive is unzipped with ditto, which only the Mac has.
#if DEBUG && os(macOS)
    @testable import DebugDrawer
    import Foundation
    import Testing

    @MainActor
    @Suite("Bug report archives", .timeLimit(.minutes(1)))
    struct ReportArchiveTests {
        @Test("Create Report zips a summary and every adopter's files, each text, JSON, HAR or PNG, redacted, and nothing of a non-adopter")
        func createReportWritesTheArchive() throws {
            let workspace = FileManager.default.temporaryDirectory.appendingPathComponent("ReportArchiveTests-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: workspace) }
            let drawer = DebugDrawer.shared
            let previousRedaction = drawer.redaction
            drawer.redaction = .standard
            drawer.registerGlobal(ReportSilentPlugin())
            drawer.registerGlobal(ReportNotesPlugin())
            drawer.registerGlobal(ReportHeadersPlugin())
            let expectedFiles = ["Headers/headers.txt", "Notes/counts.json", "Notes/notes.txt", "summary.txt"]
            let allowedExtensions: Set = ["txt", "json", "har", "png"]

            let zip = Result { try drawer.createReport(in: workspace.appendingPathComponent("out")) }

            // Leave the shared drawer as the other suites expect it, within this one main-actor turn.
            drawer.unregisterGlobal(id: ReportSilentPlugin().id)
            drawer.unregisterGlobal(id: ReportNotesPlugin().id)
            drawer.unregisterGlobal(id: ReportHeadersPlugin().id)
            drawer.redaction = previousRedaction

            let unzipped = workspace.appendingPathComponent("unzipped")
            let ditto = Process()
            ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            ditto.arguments = ["-x", "-k", try zip.get().path, unzipped.path]
            try ditto.run()
            ditto.waitUntilExit()
            let folders = try FileManager.default.contentsOfDirectory(atPath: unzipped.path)
            let folder = try #require(folders.first)
            let root = unzipped.appendingPathComponent(folder)
            let paths = try #require(FileManager.default.subpaths(atPath: root.path))
            var isDirectory: ObjCBool = false
            let files = paths.filter {
                FileManager.default.fileExists(atPath: root.appendingPathComponent($0).path, isDirectory: &isDirectory) && !isDirectory.boolValue
            }.sorted()
            let headers = try String(contentsOf: root.appendingPathComponent("Headers/headers.txt"), encoding: .utf8)
            let counts = try Data(contentsOf: root.appendingPathComponent("Notes/counts.json"))
            let summary = try String(contentsOf: root.appendingPathComponent("summary.txt"), encoding: .utf8)

            #expect(ditto.terminationStatus == 0)
            #expect(folders.count == 1)
            #expect(folder.contains("-Report-"))
            #expect(files == expectedFiles)
            #expect(files.allSatisfy { allowedExtensions.contains(URL(fileURLWithPath: $0).pathExtension) })
            #expect(headers.contains("Authorization: [REDACTED]"))
            #expect(!headers.contains("s3cr3t"))
            #expect(try JSONSerialization.jsonObject(with: counts) is [String: Any])
            #expect(summary.contains("Notes/\n  notes.txt\n  counts.json\n"))
            #expect(!summary.contains("Silent"))
        }
    }
#endif
