// Exit tests start a child process, which only the Mac's test runs can do. Each child installs
// the plugin's handlers and crashes; the parent reads the files the child left in a directory
// it passed in.
#if os(macOS) && DEBUG
    import DebugDrawer
    @testable import DebugDrawerCrashReportsPlugin
    import Darwin
    import Foundation
    import Testing

    /// The marker the stand-in for a crash SDK's handler writes, set in the child before it
    /// crashes.
    nonisolated(unsafe) private var markerPath: UnsafeMutablePointer<CChar>?

    /// A crash SDK's signal handler: writes the marker, then lets the signal take its default
    /// action, as such a handler does after recording the crash.
    private func previousSignalHandler(_ signal: Int32, _: UnsafeMutablePointer<__siginfo>?, _: UnsafeMutableRawPointer?) {
        if let markerPath {
            let file = open(markerPath, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
            _ = write(file, "signal", 6)
            close(file)
        }
        var fallback = sigaction()
        sigaction(signal, &fallback, nil)
        raise(signal)
    }

    /// A crash SDK's uncaught-exception handler: writes the marker.
    private func previousExceptionHandler(_ exception: NSException) {
        if let markerPath {
            FileManager.default.createFile(atPath: String(cString: markerPath), contents: Data(exception.name.rawValue.utf8))
        }
    }

    /// Recurses until the stack runs out; the test on `depth` keeps the compiler from calling it
    /// endless.
    @inline(never)
    private func recurse(_ depth: Int) -> Int {
        var frame = (depth, depth, depth, depth)
        frame.1 += 1
        return depth >= 0 ? recurse(depth + 1) + frame.1 : frame.0
    }

    @Suite(.timeLimit(.minutes(1)))
    struct CrashCaptureExitTests {
        @Test("A fatal signal is written with its frames, then the handler installed before still runs")
        func signalChains() async throws {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let path = directory.path(percentEncoded: false)

            await #expect(processExitsWith: .signal(SIGSEGV)) { [home = home as String, path = path as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_SUCCESS) }
                markerPath = strdup(path + "/marker")
                var previous = sigaction()
                previous.__sigaction_u.__sa_sigaction = previousSignalHandler
                previous.sa_flags = SA_SIGINFO
                sigaction(SIGSEGV, &previous, nil)
                await CrashReports.install(directory: URL(filePath: path))
                // A fault, not raise(3): a signal raised on a Swift concurrency thread, which
                // blocks signals, is delivered to another thread.
                UnsafeMutablePointer<Int>(bitPattern: 16)?.pointee = 1
            }

            let text = try String(contentsOf: directory.appending(path: "crash.txt"), encoding: .utf8)
            let actual = try #require(CrashFile.parse(text, id: UUID(), fallbackDate: .distantPast))
            #expect(actual.title == "SIGSEGV")
            #expect(actual.frames.first?.contains("DebugDrawerCrashReportsPluginTests") == true)
            let marker = try String(contentsOf: directory.appending(path: "marker"), encoding: .utf8)
            #expect(marker == "signal")
        }

        @Test("A Swift runtime failure is written as SIGTRAP with the frame that failed, and still ends the app")
        func swiftTrap() async throws {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let path = directory.path(percentEncoded: false)

            await #expect(processExitsWith: .signal(SIGTRAP)) { [home = home as String, path = path as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_SUCCESS) }
                await CrashReports.install(directory: URL(filePath: path))
                let missing: Int? = path.isEmpty ? 1 : nil
                _ = missing!
            }

            let text = try String(contentsOf: directory.appending(path: "crash.txt"), encoding: .utf8)
            let actual = try #require(CrashFile.parse(text, id: UUID(), fallbackDate: .distantPast))
            #expect(actual.title == "SIGTRAP")
            #expect(actual.frames.contains { $0.contains("DebugDrawerCrashReportsPluginTests") })
        }

        @Test("An uncaught exception is written with its reason and stack, then the handler installed before still runs")
        func exceptionChains() async throws {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let path = directory.path(percentEncoded: false)

            await #expect(processExitsWith: .signal(SIGABRT)) { [home = home as String, path = path as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_SUCCESS) }
                markerPath = strdup(path + "/marker")
                NSSetUncaughtExceptionHandler(previousExceptionHandler)
                await CrashReports.install(directory: URL(filePath: path))
                NSException(name: .invalidArgumentException, reason: "index 5 beyond bounds", userInfo: nil).raise()
            }

            let text = try String(contentsOf: directory.appending(path: "crash.txt"), encoding: .utf8)
            let actual = try #require(CrashFile.parse(text, id: UUID(), fallbackDate: .distantPast))
            #expect(actual.title == "NSInvalidArgumentException")
            #expect(actual.reason == "index 5 beyond bounds")
            #expect(actual.frames.contains { $0.contains("objc_exception_throw") })
            #expect(text.contains("\nsignal 6\n"))
            let marker = try String(contentsOf: directory.appending(path: "marker"), encoding: .utf8)
            #expect(marker == NSExceptionName.invalidArgumentException.rawValue)
        }

        @Test("A stack overflow on the thread that installed is still written, on the alternate stack")
        func stackOverflow() async throws {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let path = directory.path(percentEncoded: false)

            await #expect(processExitsWith: .failure) { [home = home as String, path = path as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_SUCCESS) }
                await MainActor.run {
                    CrashReports.install(directory: URL(filePath: path))
                    _ = recurse(0)
                }
            }

            let text = try String(contentsOf: directory.appending(path: "crash.txt"), encoding: .utf8)
            let actual = try #require(CrashFile.parse(text, id: UUID(), fallbackDate: .distantPast))
            #expect(["SIGSEGV", "SIGBUS"].contains(actual.title))
            #expect(actual.frames.contains { $0.contains("recurse") })
        }

        @Test("Installing keeps the last run's crash, registers the plugin with a badge and posts a toast")
        func installCollects() async throws {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let crash = "DebugDrawer crash report 1\ntime 1763290000\nsignal 11\nframes\n0 Example 0x1\nend\n"
            try Data(crash.utf8).write(to: directory.appending(path: "crash.txt"))
            let path = directory.path(percentEncoded: false)

            await #expect(processExitsWith: .success) { [home = home as String, path = path as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                let isInstalled = await MainActor.run {
                    CrashReports.install(directory: URL(filePath: path))
                    CrashReports.install(directory: URL(filePath: path))
                    let drawer = DebugDrawer.shared
                    return drawer.globalPlugins.count { $0.id == "CrashReportsPlugin" } == 1
                        && drawer.badges["CrashReportsPlugin"] == 1
                        && drawer.toast?.message == "The app crashed last time: SIGSEGV"
                }
                exit(isInstalled ? EXIT_SUCCESS : EXIT_FAILURE)
            }

            #expect(!FileManager.default.fileExists(atPath: path + "/crash.txt"))
            #expect(await CrashReportStore(directory: directory).reports.map(\.title) == ["SIGSEGV"])
        }
    }
#endif
