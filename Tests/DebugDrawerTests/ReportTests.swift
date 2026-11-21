#if DEBUG
    @testable import DebugDrawer
    import Foundation
    import SwiftUI
    import Testing

    struct ReportNotesPlugin: DebugDrawerPlugin, DebugDrawerReportContributor {
        var title = "Notes"
        var icon = "note.text"
        var body: some View { EmptyView() }

        func contribute(to report: inout DebugDrawerReport, redaction: DebugDrawerRedaction) {
            report.add(text: "first note", named: "notes.txt")
            report.add(jsonData: Data(#"{"count":1}"#.utf8), named: "counts")
        }
    }

    struct ReportSilentPlugin: DebugDrawerPlugin {
        var title = "Silent"
        var icon = "speaker.slash"
        var body: some View { EmptyView() }
    }

    struct ReportHeadersPlugin: DebugDrawerPlugin, DebugDrawerReportContributor {
        var title = "Headers"
        var icon = "list.bullet"
        var body: some View { EmptyView() }

        func contribute(to report: inout DebugDrawerReport, redaction: DebugDrawerRedaction) {
            let headers = redaction.redacting(headers: ["Authorization": "Bearer s3cr3t", "Accept": "text/plain"])
            report.add(text: headers.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: "\n"), named: "headers")
        }
    }

    @MainActor
    @Suite("Bug reports")
    struct ReportTests {
        @Test("A report holds the adopting plugin's files in a folder named after its title, and nothing from a plugin that doesn't adopt")
        func nonAdoptersAreAbsent() {
            let plugins = [AnyDebugDrawerPlugin(ReportSilentPlugin()), AnyDebugDrawerPlugin(ReportNotesPlugin())]
            let expectedPaths = ["Notes/notes.txt", "Notes/counts.json"]

            let actual = DebugDrawerReport(contributionsOf: plugins, redaction: .standard)

            #expect(actual.files.map(\.path) == expectedPaths)
            #expect(!actual.files.contains { $0.folder == "Silent" })
        }

        @Test("Only a plugin that adopts the protocol contributes to the report")
        func contributorConformanceIsCaptured() {
            let adopter = AnyDebugDrawerPlugin(ReportNotesPlugin())
            let other = AnyDebugDrawerPlugin(ReportSilentPlugin())

            #expect(adopter.contributesToReport)
            #expect(!other.contributesToReport)
        }

        @Test("A second file of the same name, in any case, gets a numeric suffix")
        func namesAreUnique() {
            var sut = DebugDrawerReport()
            let expected = ["log.txt", "log-2.txt", "Log-3.txt", "log-4.txt"]

            sut.add(text: "a", named: "log.txt")
            sut.add(text: "b", named: "log.txt")
            sut.add(text: "c", named: "Log.txt")
            sut.add(text: "d", named: "log")

            #expect(sut.files.map(\.name) == expected)
        }

        @Test("A name loses separators and a leading dot, gains its kind's extension, and an empty name becomes file")
        func namesAreSanitised() {
            var sut = DebugDrawerReport()
            let expected = ["a-b-c.txt", "hidden.json", "file.har", "shot.png", "clip.mov"]

            sut.add(text: "", named: "a/b:c")
            sut.add(jsonData: Data("{}".utf8), named: ".hidden")
            sut.add(har: Data("{}".utf8), named: "")
            sut.add(png: Data(), named: "shot.PNG")
            sut.add(movie: Data(), named: "clip.MOV")

            #expect(sut.files.map(\.name) == expected)
        }

        @Test("Each file's kind decides its extension: txt, json, har, png or mov")
        func kindsHaveTheirExtensions() {
            let expected = ["txt", "json", "har", "png", "mov"]

            let actual = DebugDrawerReport.Kind.allCases.map(\.fileExtension)

            #expect(actual == expected)
        }

        @Test("JSON is pretty-printed with sorted keys")
        func jsonIsPrettyAndSorted() throws {
            var sut = DebugDrawerReport()
            let expected = """
            {
              "a" : 1,
              "b" : "two/three"
            }
            """

            try sut.add(json: ["b": AnyCodableValue.string("two/three"), "a": .number(1)], named: "values")

            let file = try #require(sut.files.first)
            #expect(file.kind == .json)
            #expect(String(bytes: file.data, encoding: .utf8) == expected)
        }

        @Test("A value that can't be encoded throws JSONEncodingFailed and adds nothing")
        func unencodableJSONThrows() {
            var sut = DebugDrawerReport()

            #expect(throws: DebugDrawerReport.JSONEncodingFailed.self) {
                try sut.add(json: Double.infinity, named: "bad")
            }
            #expect(sut.files.isEmpty)
        }

        @Test("Two plugins with the same title get folders of their own")
        func foldersAreUnique() {
            let plugins = [
                AnyDebugDrawerPlugin(ReportNotesPlugin()),
                AnyDebugDrawerPlugin(ReportNotesPlugin(title: "notes"))
            ]
            let expectedFolders = ["Notes", "Notes", "notes-2", "notes-2"]

            let actual = DebugDrawerReport(contributionsOf: plugins, redaction: .none)

            #expect(actual.files.map(\.folder) == expectedFolders)
        }

        @Test("A contributor's values pass through the drawer's redaction")
        func contributionsAreRedacted() throws {
            let plugins = [AnyDebugDrawerPlugin(ReportHeadersPlugin())]

            let actual = DebugDrawerReport(contributionsOf: plugins, redaction: .standard)

            let file = try #require(actual.files.first)
            let text = try #require(String(bytes: file.data, encoding: .utf8))
            #expect(text == "Accept: text/plain\nAuthorization: [REDACTED]")
        }

        @Test("The summary names the app, its version, the OS, the device and the date, then the files by plugin")
        func summaryText() {
            let sut = ReportSummary(
                appName: "Shop", bundleID: "com.example.shop", version: "2.1", build: "40",
                operatingSystem: "iOS Version 18.0 (Build 22A100)", deviceModel: "iPad16,6",
                date: Date(timeIntervalSince1970: 1_800_000_000)
            )
            let report = DebugDrawerReport(contributionsOf: [AnyDebugDrawerPlugin(ReportNotesPlugin())], redaction: .none)
            let expected = """
            Bug report: Shop

            Bundle ID: com.example.shop
            Version: 2.1 (40)
            OS: iOS Version 18.0 (Build 22A100)
            Device: iPad16,6
            Created: 2027-01-15T08:00:00Z

            Files:
            summary.txt
            Notes/
              notes.txt
              counts.json

            """

            let actual = sut.text(listing: report)

            #expect(actual == expected)
            #expect(sut.folderName == "Shop-Report-2027-01-15T08-00-00Z")
        }

        @Test("The summary of a report no plugin contributed to says so")
        func emptySummary() {
            let sut = ReportSummary(
                appName: "Shop", bundleID: "—", version: "—", build: "—",
                operatingSystem: "macOS", deviceModel: "Mac15,3", date: Date(timeIntervalSince1970: 0)
            )

            let actual = sut.text(listing: DebugDrawerReport())

            #expect(actual.hasSuffix("Files:\nsummary.txt\n\nNo installed plugin contributed to the report.\n"))
        }

        @Test("Writing a report puts a zip named after the app and the date in the directory")
        func writesAZip() throws {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ReportTests-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: directory) }
            let summary = ReportSummary(
                appName: "Shop", bundleID: "com.example.shop", version: "1", build: "1",
                operatingSystem: "macOS", deviceModel: "Mac15,3", date: Date(timeIntervalSince1970: 0)
            )
            let report = DebugDrawerReport(contributionsOf: [AnyDebugDrawerPlugin(ReportNotesPlugin())], redaction: .none)

            let actual = try report.writeArchive(summary: summary, in: directory)

            let data = try Data(contentsOf: actual)
            #expect(actual.lastPathComponent == "Shop-Report-1970-01-01T00-00-00Z.zip")
            #expect(data.starts(with: [0x50, 0x4B, 0x03, 0x04]))
        }

        @Test("Writing into a path that is a file throws WriteFailed")
        func unwritableDirectoryThrows() throws {
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("ReportTests-\(UUID().uuidString)")
            try Data().write(to: file)
            defer { try? FileManager.default.removeItem(at: file) }
            let summary = ReportSummary(
                appName: "Shop", bundleID: "—", version: "—", build: "—",
                operatingSystem: "macOS", deviceModel: "Mac15,3", date: Date(timeIntervalSince1970: 0)
            )

            #expect(throws: DebugDrawerReport.WriteFailed.self) {
                try DebugDrawerReport().writeArchive(summary: summary, in: file)
            }
        }

        @Test("The drawer's contributors are its global, then local, plugins that adopt the protocol, each ID once")
        func contributorsAreDeduplicated() throws {
            let suite = "ReportTests.\(#function).\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let drawer = DebugDrawer(defaults: defaults)
            drawer.registerGlobal(ReportNotesPlugin())
            drawer.registerGlobal(ReportSilentPlugin())
            drawer.registerLocal(ReportNotesPlugin())
            drawer.registerLocal(ReportHeadersPlugin())
            let expected = ["DebugDrawerTests.ReportNotesPlugin", "DebugDrawerTests.ReportHeadersPlugin"]

            let actual = drawer.reportContributors.map(\.id)

            #expect(actual == expected)
        }
    }

    /// A JSON value of either kind the test encodes.
    enum AnyCodableValue: Encodable {
        case string(String)
        case number(Int)

        func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case let .string(value): try container.encode(value)
            case let .number(value): try container.encode(value)
            }
        }
    }
#endif
