// Installing registers the plugin with the drawer of the process that runs it, and writing the
// report reads every plugin registered there, so these run in a child process each, in a file of
// their own, as exit tests need one. The README's example is here, verbatim,
// rather than in DebugDrawerTests, which links core alone.
#if os(macOS) && DEBUG
    import AppKit
    @testable import DebugDrawer
    @testable import DebugDrawerScreenRecordingPlugin
    import DebugDrawerTestSupport
    import Foundation
    import SwiftUI
    import Testing

    @Suite("Screen Recording install, in a child process", .timeLimit(.minutes(1)))
    struct ScreenRecordingInstallExitTests {
        @Test("Install registers the plugin, with a HUD readout, in the Interface category")
        func install() async {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                let isExpected = await MainActor.run {
                    ScreenRecording.install()
                    let plugin = DebugDrawer.shared.globalPlugins.first { $0.title == "Screen Recording" }
                    return plugin?.hasHUD == true && plugin?.category == "Interface" && plugin?.contributesToReport == true
                }
                exit(isExpected ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        @Test("Installing again registers the plugin once, keeping the model and taking the new capacity")
        func installAgain() async {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                let isExpected = await MainActor.run {
                    let first = ScreenRecordingInstallation.install(capacity: 5, in: .shared)
                    let second = ScreenRecordingInstallation.install(capacity: 2, in: .shared)
                    let plugins = DebugDrawer.shared.globalPlugins.count { $0.title == "Screen Recording" }
                    return plugins == 1 && first === second && second.capacity == 2
                }
                exit(isExpected ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        @Test("Installing again keeps the plugin installed rather than uninstalling it; installing after an unregister lists it again")
        func installAgainKeepsItInstalled() async {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                let isExpected = await MainActor.run {
                    let model = ScreenRecordingInstallation.install(capacity: 5, in: .shared)
                    ScreenRecordingInstallation.install(capacity: 5, in: .shared)
                    let isKeptInstalled = !model.isUninstalled
                    DebugDrawer.shared.unregisterGlobal(id: ScreenRecordingPlugin.pluginID)
                    let isUninstalled = model.isUninstalled
                        && !DebugDrawer.shared.globalPlugins.contains { $0.id == ScreenRecordingPlugin.pluginID }
                    let reinstalled = ScreenRecordingInstallation.install(capacity: 5, in: .shared)
                    return isKeptInstalled && isUninstalled && reinstalled === model && !model.isUninstalled
                        && DebugDrawer.shared.globalPlugins.count { $0.id == ScreenRecordingPlugin.pluginID } == 1
                }
                exit(isExpected ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        @Test("Installing with a capacity below one traps")
        func zeroCapacityTraps() async {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .failure) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_SUCCESS) }
                await MainActor.run {
                    ScreenRecording.install(capacity: 0)
                }
            }
        }

        @Test("Installing on a drawer of its own with a capacity below one traps too")
        func zeroCapacityTrapsOnAnyDrawer() async {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .failure) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_SUCCESS) }
                await MainActor.run {
                    ScreenRecording.install(capacity: 0, in: DebugDrawer())
                }
            }
        }

        @Test("README: Screen Recording")
        func readme() async {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                let isInstalled = await MainActor.run {
                    // At startup:
                    ScreenRecording.install()

                    // Or keep the newest ten recordings rather than five:
                    ScreenRecording.install(capacity: 10)

                    return DebugDrawer.shared.globalPlugins.count { $0.title == "Screen Recording" } == 1
                }
                exit(isInstalled ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        @Test("The bug report bundle carries the newest recording as a .mov in the plugin's folder, and none once it is deleted")
        func reportBundle() async {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                @MainActor
                func isExpected() async -> Bool {
                    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
                    let source = FakeFrameSource()
                    let model = ScreenRecordingModel(
                        folder: RecordingFolder(directory: directory.appending(path: "Recordings")), capacity: 5, frameSource: source,
                        makeWriter: { FakeMovieWriter(url: $0) },
                        now: { Date(timeIntervalSince1970: 1_763_290_000) },
                        defaults: UserDefaults(suiteName: temporarySuiteName("ScreenRecordingInstallExitTests")) ?? .standard
                    )
                    DebugDrawer.shared.registerGlobal(ScreenRecordingPlugin(model: model))
                    model.start()
                    source.send(at: 1)
                    await model.stop()

                    func listing(of zip: URL) -> String {
                        let unzip = Process()
                        unzip.executableURL = URL(filePath: "/usr/bin/unzip")
                        unzip.arguments = ["-l", zip.path]
                        let output = Pipe()
                        unzip.standardOutput = output
                        try? unzip.run()
                        unzip.waitUntilExit()
                        return String(bytes: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    }
                    guard let withMovie = try? DebugDrawer.shared.createReport(in: directory.appending(path: "With")) else { return false }
                    let included = listing(of: withMovie)
                    if let recording = model.recordings.first { model.delete(recording) }
                    guard let withoutMovie = try? DebugDrawer.shared.createReport(in: directory.appending(path: "Without")) else { return false }
                    let omitted = listing(of: withoutMovie)

                    return included.contains("Screen Recording/Screen Recording 2025-11-16T10-46-40Z.mov")
                        && included.contains("summary.txt")
                        && !omitted.contains(".mov")
                        && omitted.contains("summary.txt")
                }
                exit(await isExpected() ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }
    }
#endif
