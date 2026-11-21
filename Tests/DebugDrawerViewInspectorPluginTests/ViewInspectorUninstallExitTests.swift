// Exit tests start a child process, which only the Mac's test runs can do. The overlays, the
// animation speed and the render tracker are the process's one set, which other suites read at
// the same time, so uninstalling, which turns them all off, runs only in a child.
#if os(macOS) && DEBUG
    @testable import DebugDrawer
    import DebugDrawerTestSupport
    @testable import DebugDrawerViewInspectorPlugin
    import Foundation
    import SwiftUI
    import Testing
    import ViewInspector

    /// A row whose body is tracked under a name of the test's own.
    private struct TrackedRow: View {
        let name: String

        var body: some View {
            Text("row")
                .trackRenders(name)
        }
    }

    @Suite(.timeLimit(.minutes(1)))
    struct ViewInspectorUninstallExitTests {
        @Test("Removing the plugin turns overlays, flashes and slowed animations off and stops counting renders; a reinstall counts")
        func uninstallTurnsEverythingOff() async {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                @MainActor
                func uninstallThenReinstall() throws {
                    let suite = temporarySuiteName("ViewInspectorUninstallExitTests")
                    let defaults = try #require(UserDefaults(suiteName: suite))
                    defer { defaults.removePersistentDomain(forName: suite) }
                    let drawer = DebugDrawer(defaults: defaults)
                    let controller = ViewBorderController.shared
                    let tracker = RenderTracker.shared
                    let name = "Uninstalled-\(UUID().uuidString)"
                    drawer.installViewInspector()
                    controller.isBordersEnabled = true
                    controller.isGridEnabled = true
                    controller.isClickIndicatorEnabled = true
                    controller.animationSpeed = 5
                    RenderFlashSetting.shared.isOn = true
                    _ = try TrackedRow(name: name).inspect().findAll(ViewType.Text.self)
                    let countedWhileInstalled = tracker.counts[name, default: 0]

                    drawer.unregisterGlobal(id: ViewInspectorPlugin().id)
                    let countsAfterUninstall = tracker.counts
                    _ = try TrackedRow(name: name).inspect().findAll(ViewType.Text.self)
                    let countedWhileUninstalled = tracker.counts[name, default: 0]
                    drawer.unregisterGlobal(id: ViewInspectorPlugin().id)
                    drawer.installViewInspector()
                    _ = try TrackedRow(name: name).inspect().findAll(ViewType.Text.self)
                    let countedReinstalled = tracker.counts[name, default: 0]
                    drawer.unregisterGlobal(id: ViewInspectorPlugin().id)

                    #expect(countedWhileInstalled > 0)
                    #expect(!drawer.globalPlugins.contains { $0.id == ViewInspectorPlugin().id })
                    #expect(!controller.isBordersEnabled)
                    #expect(!controller.isGridEnabled)
                    #expect(!controller.isClickIndicatorEnabled)
                    #expect(controller.animationSpeed == 1)
                    #expect(!RenderFlashSetting.shared.isOn)
                    #expect(countsAfterUninstall.isEmpty)
                    #expect(countedWhileUninstalled == 0)
                    #expect(countedReinstalled > 0)
                }
                try await MainActor.run { try uninstallThenReinstall() }
            }
        }
    }
#endif
