// Exit tests start a child process, which only the Mac's test runs can do. Capture redirects the
// process's stdout and stderr, so it is installed only in a child.
#if os(macOS) && DEBUG
    import DebugDrawer
    @testable import DebugDrawerConsolePlugin
    import Foundation
    import Testing

    @Suite(.timeLimit(.minutes(1)))
    struct ConsoleCaptureExitTests {
        @Test("The app keeps writing to stdout and stderr after the console captures them")
        func writesAfterInstall() async {
            await #expect(processExitsWith: .success) {
                await MainActor.run { ConsoleLogStore.shared.install() }
                let line = Data("Captured by the console\n".utf8)

                for _ in 0 ..< 100 {
                    FileHandle.standardOutput.write(line)
                    FileHandle.standardError.write(line)
                }
            }
        }
    }
#endif
