// The release build. `--config=release` builds and runs only the performance targets, so this is
// where the capability is tested compiled without DEBUG, as a production app's build is: through
// the public API, a real receiver and the command files a sidecar leaves in its store (the
// sidecar's transports are debug-build types). It shows that spoofing works in release and that the
// host is told as it starts and as the session's end reverts it. In debug the file is empty;
// LocationSpoofingReceiverTests covers the same with a clock and timer of the test's own.
#if !DEBUG
    import CoreLocation
    import DebugDrawerLocation
    import DebugDrawerReceiver
    import Foundation
    import Testing

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct ReleaseLocationSpoofingTests {
        @Test("In release, a sidecar's spoof replaces the host's readings and tells the host, and the session's end tells it nil")
        func spoofsAndRevertsInRelease() throws {
            let suite = "ReleaseLocationSpoofingTests-\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let directory = FileManager.default.temporaryDirectory.appending(path: "ReleaseLocationSpoofingTests-\(UUID().uuidString)")
            let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
            #expect(layout.create())
            let paris = LocationCoordinate(latitude: 48.8566, longitude: 2.3522)
            let commands: [(String, Data)] = try [
                (DebugDrawerSessions.pluginID, TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 60))),
                (LocationSpoofing.pluginID, TransportMessage.payload(LocationSpoofing.Command.spoof(paris)))
            ]
            for (index, (id, payload)) in commands.enumerated() {
                let document = StoreDocument(TransportMessage(kind: .command, pluginID: id, payload: payload))
                try layout.write(document.encoded(), to: layout.commands.appending(path: "\(index).json"))
            }
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            var told: [LocationCoordinate?] = []
            let spoofing = LocationSpoofing(sessions: sessions, defaults: defaults) { told.append($0.map { LocationCoordinate($0.coordinate) }) }
            let receiver = DebugDrawerReceiver(directory: directory, sessions: sessions)
            receiver.enable(.locationSpoofing(spoofing))
            let real = CLLocation(latitude: 37.3349, longitude: -122.009)

            try receiver.start()
            defer { receiver.stop() }
            let readDuringSession = spoofing.locations(replacing: [real]).map { LocationCoordinate($0.coordinate) }
            sessions.end()

            let expectedTold: [LocationCoordinate?] = [paris, nil]
            #expect(readDuringSession == [paris])
            #expect(told == expectedTold)
            #expect(spoofing.locations(replacing: [real]) == [real])
            #expect(sessions.auditLog.map(\.event).contains(.changeReverted))
        }
    }
#endif
