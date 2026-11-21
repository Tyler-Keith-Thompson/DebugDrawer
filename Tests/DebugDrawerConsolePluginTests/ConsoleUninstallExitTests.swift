// Exit tests start a child process, which only the Mac's test runs can do. Installing the console
// redirects the process's stdout and stderr and registers an os_log driver with OSLogClient, which
// is set up once a process, so it happens only in a child.
#if os(macOS) && DEBUG
    @testable import DebugDrawer
    @testable import DebugDrawerConsolePlugin
    import DebugDrawerTestSupport
    import Foundation
    import OSLogClient
    import Testing

    @Suite("Console uninstall, in a child process", .timeLimit(.minutes(1)))
    struct ConsoleUninstallExitTests {
        @Test("Registering the plugin globally lists it among the drawer's global plugins")
        func registration() async {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                let isListed = await MainActor.run {
                    let drawer = DebugDrawer.shared
                    drawer.registerGlobal(ConsolePlugin())
                    return drawer.globalPlugins.contains { $0.title == "Console" }
                }
                exit(isListed ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        @Test("Unregistering points stdout and stderr back at their files, removes the os_log driver and drops the lines; installing again captures")
        func uninstallRestoresTheStreams() async {
            await #expect(processExitsWith: .success) {
                useHomeFolderOfItsOwn()
                /// The file a descriptor is open on, as its device and inode.
                func identity(of fd: Int32) -> String {
                    var info = stat()
                    guard fstat(fd, &info) == 0 else { return "none" }
                    return "\(info.st_dev):\(info.st_ino)"
                }

                @MainActor
                func waitForLine(_ text: String) async {
                    for await lines in ConsoleLogStore.shared.$lines.values where lines.contains(where: { $0.text == text }) {
                        return
                    }
                }

                @MainActor
                func isExpected() async -> Bool {
                    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
                    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    let outPath = directory.appending(path: "stdout.txt").path
                    let errPath = directory.appending(path: "stderr.txt").path
                    dup2(open(outPath, O_WRONLY | O_CREAT | O_TRUNC, 0o644), STDOUT_FILENO)
                    dup2(open(errPath, O_WRONLY | O_CREAT | O_TRUNC, 0o644), STDERR_FILENO)
                    let expectedOut = identity(of: STDOUT_FILENO)
                    let expectedErr = identity(of: STDERR_FILENO)
                    let store = ConsoleLogStore.shared

                    DebugDrawer.shared.installConsole(sessions: .off)
                    let isRedirected = identity(of: STDOUT_FILENO) != expectedOut && identity(of: STDERR_FILENO) != expectedErr
                    FileHandle.standardOutput.write(Data("Captured before\n".utf8))
                    await waitForLine("Captured before")
                    await ConsoleCapture.osLogSettled()
                    let isDriverRegistered = await OSLogClient.isDriverRegistered(withId: ConsoleCapture.driver.id)

                    DebugDrawer.shared.unregisterGlobal(id: "ConsolePlugin")
                    DebugDrawer.shared.unregisterGlobal(id: "ConsolePlugin")
                    let isRestored = identity(of: STDOUT_FILENO) == expectedOut && identity(of: STDERR_FILENO) == expectedErr
                    let isDropped = store.lines.isEmpty && store.capture == .stopped
                    await ConsoleCapture.osLogSettled()
                    let isDriverRemoved = await !OSLogClient.isDriverRegistered(withId: ConsoleCapture.driver.id)
                    FileHandle.standardOutput.write(Data("Written after\n".utf8))
                    FileHandle.standardError.write(Data("Errored after\n".utf8))
                    ConsoleLogSink.log(level: .info, message: "Sunk after")
                    let isSinkDropped = store.lines.isEmpty
                    let out = (try? String(contentsOfFile: outPath, encoding: .utf8)) ?? ""
                    let err = (try? String(contentsOfFile: errPath, encoding: .utf8)) ?? ""

                    DebugDrawer.shared.installConsole(sessions: .off)
                    FileHandle.standardOutput.write(Data("Captured again\n".utf8))
                    await waitForLine("Captured again")
                    await ConsoleCapture.osLogSettled()
                    let isDriverBack = await OSLogClient.isDriverRegistered(withId: ConsoleCapture.driver.id)
                    let isRecaptured = identity(of: STDOUT_FILENO) != expectedOut
                        && !store.lines.contains { ["Written after", "Errored after", "Sunk after"].contains($0.text) }

                    return isRedirected && isDriverRegistered && isRestored && isDropped && isDriverRemoved && isSinkDropped
                        && out.contains("Captured before\n") && out.hasSuffix("Written after\n") && err.hasSuffix("Errored after\n")
                        && isDriverBack && isRecaptured
                }
                exit(await isExpected() ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        @Test("The app's install() keeps capturing after the plugin is unregistered, until its uninstall()")
        func appInstallOutlivesThePlugin() async {
            await #expect(processExitsWith: .success) {
                useHomeFolderOfItsOwn()
                let isExpected = await MainActor.run {
                    let store = ConsoleLogStore.shared
                    store.install()
                    DebugDrawer.shared.installConsole(sessions: .off)
                    DebugDrawer.shared.unregisterGlobal(id: "ConsolePlugin")
                    let isRunningWithoutThePlugin = store.capture == .running
                    store.uninstall()
                    store.uninstall()
                    return isRunningWithoutThePlugin && store.capture == .stopped
                }
                exit(isExpected ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        @Test("In two drawers the console captures until the last one uninstalls the plugin")
        func twoDrawers() async {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                let isExpected = await MainActor.run {
                    let suite = "ConsoleUninstallExitTests.\(UUID().uuidString)"
                    guard let defaults = UserDefaults(suiteName: suite) else { return false }
                    let first = DebugDrawer(defaults: defaults)
                    let second = DebugDrawer(defaults: defaults)
                    first.registerGlobal(ConsolePlugin())
                    second.registerGlobal(ConsolePlugin())

                    first.unregisterGlobal(id: "ConsolePlugin")
                    let isRunningWithOneLeft = ConsoleLogStore.shared.capture == .running
                    second.unregisterGlobal(id: "ConsolePlugin")

                    return isRunningWithOneLeft && ConsoleLogStore.shared.capture == .stopped
                        && !second.globalPlugins.contains { $0.id == "ConsolePlugin" }
                }
                exit(isExpected ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }
    }
#endif
