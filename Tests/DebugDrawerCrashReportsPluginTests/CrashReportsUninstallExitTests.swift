// Uninstalling puts back the signal actions, the uncaught-exception handler and the alternate
// stack of the process that runs it, so these run in a child process each, in a file of their
// own, as exit tests need one.
#if os(macOS) && DEBUG
    @testable import DebugDrawer
    @testable import DebugDrawerCrashReportsPlugin
    import Darwin
    import Foundation
    import Testing

    /// The marker the stand-in for a crash SDK's handler writes, set in the child before it
    /// crashes.
    nonisolated(unsafe) private var sdkMarkerPath: UnsafeMutablePointer<CChar>?
    /// The action the stand-in for a crash SDK found when it installed: the plugin's.
    nonisolated(unsafe) private var sdkPreviousAction = sigaction()

    /// An app's own signal handler, installed before the plugin.
    private func appSignalHandler(_ signal: Int32, _: UnsafeMutablePointer<__siginfo>?, _: UnsafeMutableRawPointer?) {
        var fallback = sigaction()
        sigaction(signal, &fallback, nil)
        raise(signal)
    }

    /// An app's own uncaught-exception handler, installed before the plugin.
    private func appExceptionHandler(_: NSException) {}

    /// A crash SDK's signal handler installed after the plugin: writes the marker, then calls the
    /// action it found, as such a handler does.
    private func sdkSignalHandler(_ signal: Int32, _ info: UnsafeMutablePointer<__siginfo>?, _ context: UnsafeMutableRawPointer?) {
        if let sdkMarkerPath {
            let file = open(sdkMarkerPath, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
            _ = write(file, "sdk", 3)
            close(file)
        }
        if sdkPreviousAction.sa_flags & SA_SIGINFO != 0, let handler = sdkPreviousAction.__sigaction_u.__sa_sigaction {
            handler(signal, info, context)
        }
    }

    @Suite("Crash Reports uninstall, in a child process", .timeLimit(.minutes(1)))
    struct CrashReportsUninstallExitTests {
        @Test("Unregistering puts back the signal actions, exception handler and alternate stack; again changes nothing")
        func restoresHandlers() async throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let path = directory.path(percentEncoded: false)

            await #expect(processExitsWith: .success) { [path = path as String] in
                @MainActor func isRestored() -> Bool {
                    func signalHandlers() -> [UInt] {
                        CrashCapture.signals.map { signal in
                            var action = sigaction()
                            sigaction(signal, nil, &action)
                            return unsafeBitCast(action.__sigaction_u.__sa_handler, to: UInt.self)
                        }
                    }
                    func exceptionHandler() -> UInt? {
                        NSGetUncaughtExceptionHandler().map { unsafeBitCast($0, to: UInt.self) }
                    }
                    // The stack's address while one is on, or nil: a turned-off stack keeps the
                    // address it had.
                    func alternateStack() -> Int? {
                        var stack = stack_t()
                        sigaltstack(nil, &stack)
                        return stack.ss_flags & SS_DISABLE == 0 ? Int(bitPattern: stack.ss_sp) : nil
                    }
                    var app = sigaction()
                    app.__sigaction_u.__sa_sigaction = appSignalHandler
                    app.sa_flags = SA_SIGINFO
                    sigaction(SIGSEGV, &app, nil)
                    NSSetUncaughtExceptionHandler(appExceptionHandler)
                    let expectedHandlers = signalHandlers()
                    let expectedException = exceptionHandler()
                    let expectedStack = alternateStack()
                    let directory = URL(filePath: path, directoryHint: .isDirectory)

                    CrashReports.install(directory: directory)
                    let installed = signalHandlers()
                    let installedException = exceptionHandler()
                    let installedStack = alternateStack()
                    DebugDrawer.shared.unregisterGlobal(id: CrashReportsPlugin.pluginID)
                    let uninstalled = (signalHandlers(), exceptionHandler(), alternateStack())
                    DebugDrawer.shared.unregisterGlobal(id: CrashReportsPlugin.pluginID)
                    let twice = (signalHandlers(), exceptionHandler(), alternateStack())
                    CrashReports.install(directory: directory)
                    let reinstalled = signalHandlers()
                    DebugDrawer.shared.unregisterGlobal(id: CrashReportsPlugin.pluginID)
                    let actual = (signalHandlers(), exceptionHandler(), alternateStack())

                    let expected = (expectedHandlers, expectedException, expectedStack)
                    return zip(installed, expectedHandlers).allSatisfy { $0 != $1 } && installedException != expectedException
                        && installedStack != expectedStack && reinstalled == installed
                        && uninstalled == expected && twice == expected && actual == expected
                        && !DebugDrawer.shared.globalPlugins.contains { $0.id == CrashReportsPlugin.pluginID }
                }
                exit(await MainActor.run { isRestored() } ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        @Test("In two drawers it captures until the last removes it, which drops its reports but not their files")
        func twoDrawers() async throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let path = directory.path(percentEncoded: false)

            await #expect(processExitsWith: .success) { [path = path as String] in
                @MainActor func isExpected() -> Bool {
                    func segvHandler() -> UInt {
                        var action = sigaction()
                        sigaction(SIGSEGV, nil, &action)
                        return unsafeBitCast(action.__sigaction_u.__sa_handler, to: UInt.self)
                    }
                    let suite = "CrashReportsUninstallExitTests.\(UUID().uuidString)"
                    guard let first = UserDefaults(suiteName: suite + ".first"), let second = UserDefaults(suiteName: suite + ".second") else {
                        return false
                    }
                    let firstDrawer = DebugDrawer(defaults: first)
                    let secondDrawer = DebugDrawer(defaults: second)
                    let directory = URL(filePath: path, directoryHint: .isDirectory)
                    let store = CrashReportStore(directory: directory)
                    store.add(CrashReport(
                        id: UUID(), date: Date(timeIntervalSince1970: 1), title: "SIGSEGV", reason: nil, appVersion: nil,
                        frames: [], source: .captured, isSeen: false
                    ))
                    let sut = CrashReportsPlugin(store: store)
                    let expectedHandler = segvHandler()

                    firstDrawer.registerGlobal(sut)
                    secondDrawer.registerGlobal(sut)
                    firstDrawer.unregisterGlobal(id: sut.id)
                    let handlerWhileInSecond = segvHandler()
                    let reportsWhileInSecond = store.reports.count
                    secondDrawer.unregisterGlobal(id: sut.id)
                    let handlerAfterLast = segvHandler()
                    let reportsAfterLast = store.reports.count
                    let files = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
                    firstDrawer.registerGlobal(sut)
                    let reportsReinstalled = store.reports.count
                    let handlerReinstalled = segvHandler()
                    firstDrawer.unregisterGlobal(id: sut.id)

                    return handlerWhileInSecond != expectedHandler && reportsWhileInSecond == 1
                        && handlerAfterLast == expectedHandler && reportsAfterLast == 0
                        && !secondDrawer.globalPlugins.contains { $0.id == sut.id }
                        && files.count { $0.hasSuffix(".json") } == 1
                        && reportsReinstalled == 1 && handlerReinstalled == handlerWhileInSecond
                        && segvHandler() == expectedHandler
                }
                exit(await MainActor.run { isExpected() } ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        @Test("Under a crash SDK's handler installed since, the plugin's stays and passes the crash on, writing nothing")
        func keptUnderAnotherHandler() async throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let path = directory.path(percentEncoded: false)

            await #expect(processExitsWith: .signal(SIGSEGV)) { [path = path as String] in
                sdkMarkerPath = strdup(path + "/marker")
                await MainActor.run {
                    CrashReports.install(directory: URL(filePath: path, directoryHint: .isDirectory))
                    var sdk = sigaction()
                    sdk.__sigaction_u.__sa_sigaction = sdkSignalHandler
                    sdk.sa_flags = SA_SIGINFO
                    sigaction(SIGSEGV, &sdk, &sdkPreviousAction)
                    DebugDrawer.shared.unregisterGlobal(id: CrashReportsPlugin.pluginID)
                }
                // A fault, not raise(3): a signal raised on a Swift concurrency thread, which
                // blocks signals, is delivered to another thread.
                UnsafeMutablePointer<Int>(bitPattern: 16)?.pointee = 1
            }

            let marker = try String(contentsOf: directory.appending(path: "marker"), encoding: .utf8)
            #expect(marker == "sdk")
            #expect(!FileManager.default.fileExists(atPath: path + "/crash.txt"))
        }
    }
#endif
