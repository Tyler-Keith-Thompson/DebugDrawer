// Exit tests sit apart from the other tests: builds for platforms that can't start a child process
// leave this file out.
#if os(macOS)
    @testable import DebugDrawerReceiver
    import DebugDrawerTestSupport
    import Foundation
    import Testing

    // That an edit survives a kill of the process, so the next launch can put it back. What the
    // allowlist refuses as it is made is in UserDefaultsValidationTests.
    @Suite
    struct UserDefaultsExitTests {
        @Test("An edit made in a session survives the app being killed during it, and the next launch puts it back")
        @MainActor
        func editSurvivesKill() async throws {
            let suite = temporarySuiteName("UserDefaultsExitTests")
            let directory = FileManager.default.temporaryDirectory.appending(path: "UserDefaultsExitTests-\(UUID().uuidString)")
            defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
            UserDefaults(suiteName: suite)?.set("free", forKey: "plan")

            await #expect(processExitsWith: .signal(SIGKILL)) { [suite = suite as String, path = directory.path as String] in
                await MainActor.run {
                    guard let defaults = UserDefaults(suiteName: suite) else { return }
                    let sessions = DebugDrawerSessions(maximumDuration: 300)
                    let receiver = DebugDrawerReceiver(directory: URL(filePath: path), sessions: sessions)
                    guard let capability = try? DebugDrawerReceiverCapability.userDefaults(
                        .choice("plan", options: ["free", "pro"]), defaults: defaults
                    ) else { return }
                    receiver.enable(capability)
                    let layout = AppGroupStoreLayout(directory: receiver.appDirectory)
                    guard layout.create(),
                          let payload = try? TransportMessage.payload(DebugDrawerUserDefaults.Command.set(key: "plan", value: .string("pro"))),
                          let document = try? StoreDocument(
                              TransportMessage(kind: .command, pluginID: DebugDrawerUserDefaults.pluginID, payload: payload)
                          ).encoded(),
                          (try? layout.write(document, to: layout.commands.appending(path: "0.json"))) != nil
                    else { return }
                    sessions.perform(.open(duration: 60))
                    try? receiver.start()
                    // Killed with the session open and the plan edited: no revert can run.
                    kill(getpid(), SIGKILL)
                }
            }
            let defaults = try #require(UserDefaults(suiteName: suite))
            let leftByKill = defaults.string(forKey: "plan")
            let model = try DebugDrawerUserDefaults(.choice("plan", options: ["free", "pro"]), defaults: defaults)

            _ = DebugDrawerReceiverCapability.userDefaults(model)

            #expect(leftByKill == "pro")
            #expect(defaults.string(forKey: "plan") == "free")
            #expect(defaults.object(forKey: DebugDrawerUserDefaults.originalValuesDefaultsKey) == nil)
        }
    }
#endif
