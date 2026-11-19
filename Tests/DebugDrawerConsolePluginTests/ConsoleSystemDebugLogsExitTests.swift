// Exit tests start a child process, which only the Mac's test runs can do. Installing the console
// redirects the process's stdout and stderr and sets the shared store, so it happens only in a
// child.
#if os(macOS) && DEBUG
    import DebugDrawer
    @testable import DebugDrawerConsolePlugin
    import DebugDrawerTestSupport
    import Foundation
    import Testing

    @Suite(.timeLimit(.minutes(1)))
    struct ConsoleSystemDebugLogsExitTests {
        @Test("installConsole(includeSystemDebugLogs: true) keeps Apple subsystems' debug lines")
        func optIn() async {
            await #expect(processExitsWith: .success) {
                useHomeFolderOfItsOwn()
                let isKept = await MainActor.run {
                    DebugDrawer.shared.installConsole(sessions: .off, includeSystemDebugLogs: true)
                    let line = LogLine(timestamp: Date(), text: "Event dispatched", source: .oslog, level: .debug, subsystem: "com.apple.UIKit")
                    return ConsoleLogStore.shared.ingestFilter.keeps(line)
                }
                exit(isKept ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        @Test("installConsole() leaves Apple subsystems' debug lines out")
        func byDefault() async {
            await #expect(processExitsWith: .success) {
                useHomeFolderOfItsOwn()
                let isKept = await MainActor.run {
                    DebugDrawer.shared.installConsole(sessions: .off)
                    let line = LogLine(timestamp: Date(), text: "Event dispatched", source: .oslog, level: .debug, subsystem: "com.apple.UIKit")
                    return ConsoleLogStore.shared.ingestFilter.keeps(line)
                }
                exit(isKept ? EXIT_FAILURE : EXIT_SUCCESS)
            }
        }
    }
#endif
