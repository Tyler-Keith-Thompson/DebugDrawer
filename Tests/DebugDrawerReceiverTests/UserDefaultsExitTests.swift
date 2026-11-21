// Exit tests sit apart from the other tests: builds for platforms that can't start a child process
// leave this file out.
#if os(macOS)
    @testable import DebugDrawerReceiver
    import DebugDrawerTestSupport
    import Foundation
    import Testing

    // The traps for an allowlist that contradicts itself or reaches for DebugDrawer's own keys, and
    // that an edit survives a kill of the process, so the next launch can put it back.
    @Suite
    struct UserDefaultsExitTests {
        @Test("An allowlisted key that is empty traps")
        func emptyKeyTraps() async {
            await #expect(processExitsWith: .failure) {
                _ = DebugDrawerUserDefaultsKey.bool("")
            }
        }

        @Test("An allowlisted key prefixed DebugDrawer. traps, so a sidecar can't edit the capability's own record")
        func ownRecordKeyTraps() async {
            await #expect(processExitsWith: .failure) {
                _ = DebugDrawerUserDefaultsKey.string(DebugDrawerUserDefaults.originalValuesDefaultsKey)
            }
        }

        @Test("An allowlisted key prefixed com.debugdrawer. traps")
        func libraryKeyTraps() async {
            await #expect(processExitsWith: .failure) {
                _ = DebugDrawerUserDefaultsKey.bool("com.debugdrawer.drawer.pinned")
            }
        }

        @Test("A string key whose maximum length isn't positive traps")
        func nonPositiveMaximumLengthTraps() async {
            await #expect(processExitsWith: .failure) {
                _ = DebugDrawerUserDefaultsKey.string("greeting", maximumLength: 0)
            }
        }

        @Test("A number key with a bound that isn't finite traps")
        func infiniteBoundTraps() async {
            await #expect(processExitsWith: .failure) {
                _ = DebugDrawerUserDefaultsKey.double("discount", in: 0 ... .infinity)
            }
        }

        @Test("A choice key without options traps")
        func emptyChoiceTraps() async {
            await #expect(processExitsWith: .failure) {
                _ = DebugDrawerUserDefaultsKey.choice("plan", options: [])
            }
        }

        @Test("A choice key whose options repeat traps")
        func repeatedOptionTraps() async {
            await #expect(processExitsWith: .failure) {
                _ = DebugDrawerUserDefaultsKey.choice("plan", options: ["free", "free"])
            }
        }

        @Test("An allowlist listing one key twice traps")
        func repeatedKeyTraps() async {
            await #expect(processExitsWith: .failure) {
                await MainActor.run {
                    _ = DebugDrawerReceiverCapability.userDefaults(.bool("showsTips"), .string("showsTips"))
                }
            }
        }

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
                    receiver.enable(.userDefaults(.choice("plan", options: ["free", "pro"]), defaults: defaults))
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
            let model = DebugDrawerUserDefaults(.choice("plan", options: ["free", "pro"]), defaults: defaults)

            _ = DebugDrawerReceiverCapability.userDefaults(model)

            #expect(leftByKill == "pro")
            #expect(defaults.string(forKey: "plan") == "free")
            #expect(defaults.object(forKey: DebugDrawerUserDefaults.originalValuesDefaultsKey) == nil)
        }
    }
#endif
