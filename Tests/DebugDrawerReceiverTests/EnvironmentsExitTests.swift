// Exit tests sit apart from the other tests: builds for platforms that can't start a child process
// leave this file out.
#if os(macOS)
    @testable import DebugDrawerReceiver
    import DebugDrawerTestSupport
    import Foundation
    import Testing

    /// A backend switch that does nothing, for a child process that only makes the model.
    @MainActor
    private final class IdleBackend: DebugDrawerEnvironmentAdapter {
        func activate(_ environment: DebugDrawerEnvironment) {}
    }

    // That a switch survives a kill of the process, so the next launch can undo it. What the
    // allowlist refuses as it is made is in EnvironmentsValidationTests.
    @Suite
    struct EnvironmentsExitTests {
        @Test("A switch made in a session survives the app being killed during it, and the next launch puts the default back")
        @MainActor
        func switchSurvivesKill() async throws {
            let suite = temporarySuiteName("EnvironmentsExitTests")
            let directory = FileManager.default.temporaryDirectory.appending(path: "EnvironmentsExitTests-\(UUID().uuidString)")
            defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }

            await #expect(processExitsWith: .signal(SIGKILL)) { [suite = suite as String, path = directory.path as String] in
                await MainActor.run {
                    guard let defaults = UserDefaults(suiteName: suite),
                          let model = try? DebugDrawerEnvironments(
                              default: DebugDrawerEnvironment("production", title: "Production"),
                              allowing: DebugDrawerEnvironment("staging", title: "Staging"),
                              adapter: IdleBackend(), defaults: defaults
                          )
                    else { return }
                    let sessions = DebugDrawerSessions(maximumDuration: 300)
                    let receiver = DebugDrawerReceiver(directory: URL(filePath: path), sessions: sessions)
                    receiver.enable(.environments(model))
                    let layout = AppGroupStoreLayout(directory: receiver.appDirectory)
                    guard layout.create(),
                          let payload = try? TransportMessage.payload(DebugDrawerEnvironments.Command.activate(environment: "staging")),
                          let document = try? StoreDocument(
                              TransportMessage(kind: .command, pluginID: DebugDrawerEnvironments.pluginID, payload: payload)
                          ).encoded(),
                          (try? layout.write(document, to: layout.commands.appending(path: "0.json"))) != nil
                    else { return }
                    sessions.perform(.open(duration: 60))
                    try? receiver.start()
                    // Killed with the session open and the app on staging: no revert can run.
                    kill(getpid(), SIGKILL)
                }
            }
            let defaults = try #require(UserDefaults(suiteName: suite))
            let recorded = defaults.string(forKey: DebugDrawerEnvironments.activeEnvironmentDefaultsKey)
            let model = try DebugDrawerEnvironments(
                default: DebugDrawerEnvironment("production", title: "Production"),
                allowing: DebugDrawerEnvironment("staging", title: "Staging"),
                adapter: IdleBackend(), defaults: defaults
            )

            _ = DebugDrawerReceiverCapability.environments(model)

            #expect(recorded == "staging")
            #expect(model.snapshot.activeEnvironment == "production")
            #expect(defaults.string(forKey: DebugDrawerEnvironments.activeEnvironmentDefaultsKey) == nil)
        }
    }
#endif
