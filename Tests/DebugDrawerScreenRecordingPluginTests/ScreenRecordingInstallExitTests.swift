// Installing registers the plugin with the drawer of the process that runs it, and writing the
// report reads every plugin registered there, so these run in a child process each, in a file of
// their own, as exit tests need one. The README's example is here, verbatim,
// rather than in DebugDrawerTests, which links core alone.
#if os(macOS) && DEBUG
    import AppKit
    @testable import DebugDrawer
    @testable import DebugDrawerScreenRecordingPlugin
    import Foundation
    import SwiftUI
    import Testing

    @Suite("Screen Recording install, in a child process")
    struct ScreenRecordingInstallExitTests {
        @Test("Install registers the plugin, with a HUD readout, in the Interface category")
        func install() async {
            await #expect(processExitsWith: .success) {
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
            await #expect(processExitsWith: .success) {
                let isExpected = await MainActor.run {
                    let first = ScreenRecordingInstallation.install(capacity: 5)
                    let second = ScreenRecordingInstallation.install(capacity: 2)
                    let plugins = DebugDrawer.shared.globalPlugins.count { $0.title == "Screen Recording" }
                    return plugins == 1 && first === second && second.capacity == 2
                }
                exit(isExpected ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        @Test("Installing again keeps the plugin installed rather than uninstalling it; installing after an unregister lists it again")
        func installAgainKeepsItInstalled() async {
            await #expect(processExitsWith: .success) {
                let isExpected = await MainActor.run {
                    let model = ScreenRecordingInstallation.install(capacity: 5)
                    ScreenRecordingInstallation.install(capacity: 5)
                    let isKeptInstalled = !model.isUninstalled
                    DebugDrawer.shared.unregisterGlobal(id: ScreenRecordingPlugin.pluginID)
                    let isUninstalled = model.isUninstalled
                        && !DebugDrawer.shared.globalPlugins.contains { $0.id == ScreenRecordingPlugin.pluginID }
                    let reinstalled = ScreenRecordingInstallation.install(capacity: 5)
                    return isKeptInstalled && isUninstalled && reinstalled === model && !model.isUninstalled
                        && DebugDrawer.shared.globalPlugins.count { $0.id == ScreenRecordingPlugin.pluginID } == 1
                }
                exit(isExpected ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        @Test("Installing with a capacity below one traps")
        func zeroCapacityTraps() async {
            await #expect(processExitsWith: .failure) {
                await MainActor.run {
                    ScreenRecording.install(capacity: 0)
                }
            }
        }

        @Test("README: Screen Recording")
        func readme() async {
            await #expect(processExitsWith: .success) {
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
            await #expect(processExitsWith: .success) {
                @MainActor
                func isExpected() async -> Bool {
                    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
                    let source = FakeFrameSource()
                    let model = ScreenRecordingModel(
                        folder: RecordingFolder(directory: directory.appending(path: "Recordings")), capacity: 5, frameSource: source,
                        makeWriter: { FakeMovieWriter(url: $0) },
                        now: { Date(timeIntervalSince1970: 1_763_290_000) },
                        defaults: UserDefaults(suiteName: UUID().uuidString) ?? .standard
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
