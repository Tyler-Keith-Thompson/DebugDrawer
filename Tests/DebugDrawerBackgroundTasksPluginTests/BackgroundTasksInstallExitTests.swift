// Installing registers the plugin with the drawer of the process that runs it, so these run in a
// child process each, in a file of their own, as exit tests need one. The README's example is
// here, verbatim, rather than in DebugDrawerTests, which links core alone.
#if os(macOS) && DEBUG
    import DebugDrawer
    @testable import DebugDrawerBackgroundTasksPlugin
    import Foundation
    import Testing

    @Suite("Background Tasks install, in a child process")
    struct BackgroundTasksInstallExitTests {
        @Test("Install registers the plugin over the Info.plist, reads the requests, and reads them again on a change")
        func install() async {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                let installed = await MainActor.run {
                    let scheduler = FakeBackgroundTaskScheduler()
                    let changes = FakeBackgroundTaskChangeSource()
                    let model = BackgroundTaskRequestsInstallation.install(
                        infoDictionary: ["BGTaskSchedulerPermittedIdentifiers": ["com.example.refresh"], "UIBackgroundModes": ["fetch"]],
                        client: scheduler, changes: changes
                    )
                    let isRegistered = DebugDrawer.shared.globalPlugins.contains { $0.title == "Background Tasks" }
                    return (model, scheduler, changes, isRegistered)
                }
                let (model, scheduler, changes, isRegistered) = installed
                await model.refresh()
                let first = await model.pending
                let request = BackgroundTaskRequest(id: "com.example.refresh", earliestBeginDate: nil, kind: .appRefresh)
                await MainActor.run { scheduler.requests = [request] }
                await changes.change()
                let second = await model.pending
                let declaration = await model.declaration
                let isCorrect = isRegistered && first == .loaded([]) && second == .loaded([request])
                    && declaration == BackgroundTaskDeclaration(identifiers: [PermittedIdentifier("com.example.refresh")], kinds: [.appRefresh])
                exit(isCorrect ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        @Test("Installing again registers the plugin once")
        func installAgain() async {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                let isExpected = await MainActor.run {
                    BackgroundTaskRequestsInstallation.install(
                        infoDictionary: [:], client: FakeBackgroundTaskScheduler(), changes: FakeBackgroundTaskChangeSource()
                    )
                    BackgroundTaskRequestsInstallation.install(
                        infoDictionary: [:], client: FakeBackgroundTaskScheduler(), changes: FakeBackgroundTaskChangeSource()
                    )
                    return DebugDrawer.shared.globalPlugins.filter { $0.title == "Background Tasks" }.count == 1
                }
                exit(isExpected ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        @Test("README: Background Tasks (on the Mac, which has no BGTaskScheduler, install adds nothing)")
        func readme() async {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                await MainActor.run {
                    // At startup, after registering the app's own launch handlers:
                    BackgroundTaskRequests.install()

                    let isInstalled = DebugDrawer.shared.globalPlugins.contains { $0.title == "Background Tasks" }
                    exit(isInstalled ? EXIT_FAILURE : EXIT_SUCCESS)
                }
            }
        }
    }
#endif
