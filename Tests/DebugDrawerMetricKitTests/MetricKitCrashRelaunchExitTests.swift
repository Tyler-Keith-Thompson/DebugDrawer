// A crash in the production app, followed through three launches, each a process of its own:
// exit tests start a child process, which only the Mac's test runs can do. The capability
// captures crashes through MetricKit alone, so the launch that crashes installs nothing in the
// crash's path; the system writes the crash's diagnostic and delivers it on a later launch.
// MetricKit can't be made to do that in a test, so the second launch's source hands the mirror a
// recorded-shape diagnostic payload (DebugDrawerTestSupport's MetricKitFixtures) through the
// subscriber's entry point, as MXMetricManager does. The third launch is the parent: a fresh
// receiver over the same directories, the public capability with the real MetricKit subscriber,
// and the sidecar's store transport, which sees the crash once it opens a session.
#if os(macOS) && DEBUG
    import DebugDrawer
    @testable import DebugDrawerMetricKit
    @testable import DebugDrawerReceiver
    import DebugDrawerTestSupport
    import Darwin
    import Foundation
    import Testing

    @Suite(.timeLimit(.minutes(1)))
    struct MetricKitCrashRelaunchExitTests {
        @Test("A crash in the production build appears in the sidecar after relaunch")
        func crashReachesSidecarAfterRelaunch() async throws {
            let root = FileManager.default.temporaryDirectory.appending(path: "MetricKitCrashRelaunchExitTests-\(UUID().uuidString)")
            let store = root.appending(path: "Group/DebugDrawer").path(percentEncoded: false)
            let archive = root.appending(path: "Application Support/Payloads").path(percentEncoded: false)

            // The launch that crashes: the receiver serves the capability, then the app faults.
            await #expect(processExitsWith: .signal(SIGSEGV)) { [store = store as String, archive = archive as String] in
                await MainActor.run {
                    let sessions = DebugDrawerSessions(maximumDuration: 300)
                    let receiver = DebugDrawerReceiver(directory: URL(filePath: store, directoryHint: .isDirectory), sessions: sessions)
                    receiver.enable(.metricKitPayloads(sessions: sessions, directory: URL(filePath: archive, directoryHint: .isDirectory)))
                    try? receiver.start()
                }
                // A fault, not raise(3): a signal raised on a Swift concurrency thread, which
                // blocks signals, is delivered to another thread.
                UnsafeMutablePointer<Int>(bitPattern: 16)?.pointee = 1
            }

            // The next launch: MetricKit delivers the crash's diagnostic as the app starts, and the
            // app is quit before anyone opens a session.
            await #expect(processExitsWith: .success) { [store = store as String, archive = archive as String] in
                /// Hands over the crash's diagnostic payload as it is subscribed.
                @MainActor
                final class NextLaunchSource: MetricKitPayloadSource {
                    func subscribe(_ receive: @escaping @MainActor ([ReceivedMetricKitPayload]) -> Void) {
                        receive([ReceivedMetricKitPayload(kind: .diagnostics, json: MetricKitFixtures.crashDiagnosticPayload)])
                    }

                    func unsubscribe() {}
                }
                let isKept = await MainActor.run {
                    let sessions = DebugDrawerSessions(maximumDuration: 300)
                    let receiver = DebugDrawerReceiver(directory: URL(filePath: store, directoryHint: .isDirectory), sessions: sessions)
                    let mirror = MetricKitPayloadsMirror(
                        sessions: sessions,
                        directory: URL(filePath: archive, directoryHint: .isDirectory),
                        redaction: .standard,
                        capacity: MetricKitPayloadsMirror.defaultCapacity,
                        source: NextLaunchSource()
                    )
                    receiver.enable(.model(mirror, id: MetricKitPayloadsMirror.pluginID, scope: .persistent))
                    try? receiver.start()
                    // Nothing is served without a session.
                    return mirror.snapshot.payloads.isEmpty
                }
                exit(isKept ? EXIT_SUCCESS : EXIT_FAILURE)
            }

            // The relaunch: a fresh receiver over the same container, and the sidecar, which reads
            // the snapshot before opening a session, then in it.
            @MainActor
            func relaunch() async throws -> (beforeSession: MetricKitPayloadsMirror.Snapshot?, during: MetricKitPayloadsMirror.Snapshot?) {
                let sessions = DebugDrawerSessions(maximumDuration: 300)
                let receiver = DebugDrawerReceiver(directory: URL(filePath: store, directoryHint: .isDirectory), sessions: sessions)
                receiver.enable(.metricKitPayloads(sessions: sessions, directory: URL(filePath: archive, directoryHint: .isDirectory)))
                try receiver.start()
                defer { receiver.stop() }
                let sidecar = try DebugDrawerAppGroupStoreTransport(directory: receiver.appDirectory)
                let sessionControl = try await sidecar.connect(
                    toPlugin: DebugDrawerSessions.pluginID, snapshot: DebugDrawerSessionState.self, command: DebugDrawerSessionCommand.self
                )
                let payloads = try await sidecar.connect(
                    toPlugin: MetricKitPayloadsMirror.pluginID,
                    snapshot: MetricKitPayloadsMirror.Snapshot.self,
                    command: MetricKitPayloadsMirror.Command.self
                )
                var arrivals = payloads.snapshots().makeAsyncIterator()
                let beforeSession = await arrivals.next()
                sessionControl.send(.open(duration: 60))
                while let snapshot = await arrivals.next() {
                    if snapshot.sessionID != nil {
                        return (beforeSession, snapshot)
                    }
                }
                return (beforeSession, nil)
            }
            let (beforeSession, during) = try await relaunch()

            #expect(beforeSession?.payloads.isEmpty == true)
            // The real subscriber may add payloads MetricKit holds for the test runner; the crash
            // is found by what it holds.
            let crashes = (during?.payloads ?? []).filter { $0.kind == .diagnostics }.compactMap { payload in
                ((try? JSONSerialization.jsonObject(with: payload.json)) as? [String: Any])?["crashDiagnostics"] as? [[String: Any]]
            }.joined()
            let ours = crashes.first { ($0["diagnosticMetaData"] as? [String: Any])?["bundleIdentifier"] as? String == "com.example.ExampleApp" }
            let crash = try #require(ours)
            let metadata = try #require(crash["diagnosticMetaData"] as? [String: Any])
            #expect(metadata["signal"] as? Int == 11)
            #expect(metadata["appVersion"] as? String == "1.2")
            let stacks = try #require((crash["callStackTree"] as? [String: Any])?["callStacks"] as? [[String: Any]])
            let crashedThread = try #require(stacks.first { $0["threadAttributed"] as? Bool == true })
            let topFrame = try #require((crashedThread["callStackRootFrames"] as? [[String: Any]])?.first)
            #expect(topFrame["binaryName"] as? String == "ExampleApp")
            #expect(topFrame["offsetIntoBinaryTextSegment"] as? Int == 123_456)
            let reason = try #require(metadata["objectiveCexceptionReason"] as? [String: Any])
            #expect(reason["composedMessage"] as? String == MetricKitRedaction.mask)
            #expect(reason["formatString"] as? String == "Can't save the profile of %@")
        }

        @Test("Enabling the capability installs no crash handler: every fatal signal's action and the uncaught-exception handler stay as they were")
        func installsNoCrashHandler() async {
            let directory = FileManager.default.temporaryDirectory.appending(path: "MetricKitCrashRelaunchExitTests-\(UUID().uuidString)")
                .path(percentEncoded: false)

            await #expect(processExitsWith: .success) { [directory = directory as String] in
                let signals: [Int32] = [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGTRAP]
                func actions() -> [UInt] {
                    signals.map { signal in
                        var action = sigaction()
                        sigaction(signal, nil, &action)
                        return unsafeBitCast(action.__sigaction_u.__sa_handler, to: UInt.self)
                    }
                }
                func exceptionHandler() -> UInt? {
                    NSGetUncaughtExceptionHandler().map { unsafeBitCast($0, to: UInt.self) }
                }
                let before = (actions(), exceptionHandler())
                let after = await MainActor.run {
                    let url = URL(filePath: directory, directoryHint: .isDirectory)
                    let sessions = DebugDrawerSessions(maximumDuration: 300)
                    let receiver = DebugDrawerReceiver(directory: url.appending(path: "Store"), sessions: sessions)
                    receiver.enable(.metricKitPayloads(sessions: sessions, directory: url.appending(path: "Payloads")))
                    try? receiver.start()
                    sessions.perform(.open(duration: 60))
                    return (actions(), exceptionHandler())
                }
                exit(before == after ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }
    }
#endif
