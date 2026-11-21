// Exit tests sit apart from the other tests: builds for platforms that can't start a child process
// leave this file out.
#if os(macOS) && DEBUG
    @testable import DebugDrawerLocation
    @testable import DebugDrawerReceiver
    import Foundation
    import Testing

    // A spoof ends with the process that was killed in it, but the host may have kept a spoofed
    // location of its own: the flag the model writes before it tells the host survives the kill, so
    // the next launch tells the host the spoof is over as it makes the capability.
    @Suite
    struct LocationSpoofingExitTests {
        @Test("A spoof made in a session survives the app being killed during it as a flag, and the next launch tells the host it is over")
        @MainActor
        func spoofLeavesFlagThroughKill() async throws {
            let suite = "LocationSpoofingExitTests-\(UUID().uuidString)"
            let directory = FileManager.default.temporaryDirectory.appending(path: "LocationSpoofingExitTests-\(UUID().uuidString)")
            defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }

            await #expect(processExitsWith: .signal(SIGKILL)) { [suite = suite as String, path = directory.path as String] in
                await MainActor.run {
                    guard let defaults = UserDefaults(suiteName: suite) else { return }
                    let sessions = DebugDrawerSessions(maximumDuration: 300)
                    let receiver = DebugDrawerReceiver(directory: URL(filePath: path), sessions: sessions)
                    let spoofing = LocationSpoofing(sessions: sessions, defaults: defaults) { _ in }
                    receiver.enable(.locationSpoofing(spoofing))
                    let layout = AppGroupStoreLayout(directory: receiver.appDirectory)
                    guard layout.create(),
                          let payload = try? TransportMessage.payload(
                              LocationSpoofing.Command.spoof(LocationCoordinate(latitude: 48.8566, longitude: 2.3522))
                          ),
                          let document = try? StoreDocument(
                              TransportMessage(kind: .command, pluginID: LocationSpoofing.pluginID, payload: payload)
                          ).encoded(),
                          (try? layout.write(document, to: layout.commands.appending(path: "0.json"))) != nil
                    else { return }
                    sessions.perform(.open(duration: 60))
                    try? receiver.start()
                    guard spoofing.isSpoofing else { return }
                    // Killed with the session open and the location spoofed: no revert can run.
                    kill(getpid(), SIGKILL)
                }
            }
            let defaults = try #require(UserDefaults(suiteName: suite))
            let flagged = defaults.bool(forKey: LocationSpoofing.spoofingDefaultsKey)
            var told: [Bool] = []
            let model = LocationSpoofing(sessions: DebugDrawerSessions(maximumDuration: 300), defaults: defaults) { told.append($0 == nil) }

            _ = DebugDrawerReceiverCapability.locationSpoofing(model)

            #expect(flagged)
            #expect(told == [true])
            #expect(!model.isSpoofing)
            #expect(defaults.object(forKey: LocationSpoofing.spoofingDefaultsKey) == nil)
        }
    }
#endif
