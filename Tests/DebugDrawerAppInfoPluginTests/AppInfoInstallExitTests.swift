// Installing registers the plugin with the drawer of the process that runs it, so these run in a
// child process each, in a file of their own, as exit tests need one. The README's example is
// here, verbatim, rather than in DebugDrawerTests, which links core alone.
#if os(macOS) && DEBUG
    import DebugDrawer
    import DebugDrawerAppInfo
    @testable import DebugDrawerAppInfoPlugin
    import Foundation
    import Testing

    @Suite("App Info install, in a child process")
    struct AppInfoInstallExitTests {
        @Test("Installing again replaces the plugin, keeping the newer build metadata")
        func installAgain() async {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                let isExpected = await MainActor.run {
                    DebugDrawer.shared.installAppInfo(buildMetadata: AppInfoBuildMetadata(gitCommit: "old"))
                    DebugDrawer.shared.installAppInfo(buildMetadata: AppInfoBuildMetadata(gitCommit: "new"))
                    var report = DebugDrawerReport()
                    let plugins = DebugDrawer.shared.globalPlugins.filter { $0.title == "App Info" }
                    plugins.first?.contribute(to: &report, redaction: .none)
                    let json = report.files.first.flatMap { try? JSONSerialization.jsonObject(with: $0.data) as? [String: [String: String]] }
                    return plugins.count == 1 && json?["Build"]?["Commit"] == "new"
                }
                exit(isExpected ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        @Test("README: App Info")
        func readme() async {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                await MainActor.run {
                    DebugDrawer.shared.installAppInfo(buildMetadata: AppInfoBuildMetadata(gitCommit: "4f9c2e1", gitBranch: "release/2.4"))

                    let plugins = DebugDrawer.shared.globalPlugins.filter { $0.title == "App Info" }
                    exit(plugins.count == 1 ? EXIT_SUCCESS : EXIT_FAILURE)
                }
            }
        }
    }
#endif
