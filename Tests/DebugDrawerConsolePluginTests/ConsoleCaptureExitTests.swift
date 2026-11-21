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
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
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
