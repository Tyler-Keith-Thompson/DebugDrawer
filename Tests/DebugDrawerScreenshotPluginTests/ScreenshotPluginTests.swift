#if DEBUG
    @testable import DebugDrawer
    @testable import DebugDrawerScreenshotPlugin
    import Foundation
    import Testing

    @MainActor
    @Suite struct ScreenshotPluginTests {
        @Test func thePluginIsTitledScreenshotWithACameraIcon() {
            let sut = ScreenshotPlugin()

            #expect(sut.title == "Screenshot")
            #expect(sut.icon == "camera")
        }

        @Test func aCaptureIsNamedForTheAppAndTheTimeWithNoColons() {
            let date = Date(timeIntervalSince1970: 1_800_000_000)
            let expected = "Orders-Debug-2027-01-15T08-00-00Z.png"

            let actual = ScreenshotFile.filename(appName: "Orders", at: date)

            #expect(actual == expected)
        }

        @Test func aWritableDirectoryGetsTheFileAndItsURLIsReported() throws {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let expectedData = Data([0x89, 0x50, 0x4E, 0x47])
            let expectedURL = directory.appendingPathComponent("capture.png")

            let actual = try ScreenshotFile.save(expectedData, as: "capture.png", in: directory)

            #expect(actual == .saved(expectedURL))
            #expect(try Data(contentsOf: expectedURL) == expectedData)
        }

        @Test func aDirectoryThatRefusesTheWriteAsksForALocationInstead() throws {
            // A read-only directory refuses a write the way the sandbox refuses ~/Desktop.
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
            defer {
                try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
                try? FileManager.default.removeItem(at: directory)
            }

            let actual = try ScreenshotFile.save(Data([1]), as: "capture.png", in: directory)

            #expect(actual == .needsLocation)
            #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("capture.png").path))
        }

        @Test func aDirectoryThatDoesNotExistThrowsRatherThanAskingForALocation() {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

            #expect(throws: CocoaError.self) {
                try ScreenshotFile.save(Data([1]), as: "capture.png", in: directory)
            }
        }
    }
#endif
