#if DEBUG
    import CoreLocation
    import DebugDrawer
    @testable import DebugDrawerLocation
    @testable import DebugDrawerReceiver
    import Foundation
    import Testing

    /// A flag service with nothing to override, so a receiver serves a capability other than
    /// location spoofing.
    @MainActor
    private final class EmptyFlagAdapter: DebugDrawerFeatureFlagAdapter {
        func overridableFlags() -> [DebugDrawerFeatureFlag] { [] }
        func setOverride(_ value: DebugDrawerFeatureFlagValue, forKey key: String) {}
        func clearOverride(forKey key: String) {}
    }

    /// A host gate the test turns on and off, standing in for a remote configuration value.
    @MainActor
    private final class Gate {
        var isOpen = true
    }

    // Location spoofing end to end through the receiver alone, as a release build links it (no
    // drawer). Criterion 1: the host's `spoofingDidChange` hears the spoof as it lands and the end
    // as the session's revert runs. Criterion 2: under a grant policy a spoof needs a grant listing
    // the capability, and `.requiringGrant()` needs one without a policy. Criterion 3: the readings
    // are real again, and the host told, as the session ends, expires, a gate turns off, and as the
    // launch after a kill makes the capability. Commands are files left in the store the way a
    // sidecar's transport leaves them; the receiver performs those waiting as it starts or
    // re-evaluates its gates. Sessions run on a clock the test moves and a timer it fires, so expiry
    // is exact and nothing waits. Each test keeps the model's flag in a defaults suite of its own.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct LocationSpoofingReceiverTests {
        private nonisolated static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        private let spoofingID = LocationSpoofing.pluginID
        private let flagsID = DebugDrawerFeatureFlagOverrides.pluginID
        private let sessionsID = DebugDrawerSessions.pluginID
        private let paris = LocationCoordinate(latitude: 48.8566, longitude: 2.3522)
        private let real = CLLocation(latitude: 37.3349, longitude: -122.009)

        @Test("A sidecar reads, from the store, that nothing is spoofed until a spoof lands")
        func servesSnapshot() async throws {
            let suite = "LocationSpoofingReceiverTests-\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let directory = FileManager.default.temporaryDirectory.appending(path: "LocationSpoofingReceiverTests-\(UUID().uuidString)")
            let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
            #expect(layout.create())
            let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: MovableClock(Self.now), timer: ManualTimer())
            let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
            let model = LocationSpoofing(sessions: sessions, defaults: defaults, now: { Self.now }, spoofingDidChange: { _ in })
            sut.enable(.locationSpoofing(model))
            let snapshotFile = layout.snapshotFile(for: spoofingID)
            let watcher = try #require(DirectoryWatcher(directory: layout.snapshots))
            defer { watcher.cancel() }

            try sut.start()
            defer { sut.stop() }
            if !FileManager.default.fileExists(atPath: snapshotFile.path) {
                for await _ in watcher.changes where FileManager.default.fileExists(atPath: snapshotFile.path) {
                    break
                }
            }

            let document = try #require(StoreDocument.decoded(from: Data(contentsOf: snapshotFile)))
            let actual = try JSONDecoder().decode(LocationSpoofing.Snapshot.self, from: document.message.payload)
            #expect(actual == LocationSpoofing.Snapshot(coordinate: nil))
            #expect(sut.enabledCapabilities == [spoofingID])
        }

        @Test("The host is told the location as a sidecar's spoof lands, and nil as the session ends, audited changeReverted")
        func hostToldOnSpoofAndOnRevert() throws {
            let suite = "LocationSpoofingReceiverTests-\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let directory = FileManager.default.temporaryDirectory.appending(path: "LocationSpoofingReceiverTests-\(UUID().uuidString)")
            let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
            #expect(layout.create())
            let payloads: [(String, Data)] = try [
                (sessionsID, TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 60))),
                (spoofingID, TransportMessage.payload(LocationSpoofing.Command.spoof(paris)))
            ]
            for (index, (id, payload)) in payloads.enumerated() {
                let document = StoreDocument(TransportMessage(kind: .command, pluginID: id, payload: payload))
                try layout.write(document.encoded(), to: layout.commands.appending(path: "\(index).json"))
            }
            let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: MovableClock(Self.now), timer: ManualTimer())
            let observer = SpoofingObserver()
            let model = LocationSpoofing(sessions: sessions, defaults: defaults, now: { Self.now }, spoofingDidChange: observer.spoofingDidChange)
            let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
            sut.enable(.locationSpoofing(model))
            try sut.start()
            defer { sut.stop() }
            let toldDuringSession = observer.told
            let readDuringSession = model.locations(replacing: [real]).map { LocationCoordinate($0.coordinate) }
            let expectedTold: [LocationCoordinate?] = [paris, nil]
            let expectedTail: [DebugDrawerAuditEntry.Event] = [.commandApplied, .changeReverted, .sessionEnded(.ended)]

            sessions.end()

            #expect(toldDuringSession == [paris])
            #expect(readDuringSession == [paris])
            #expect(observer.told == expectedTold)
            #expect(model.locations(replacing: [real]) == [real])
            #expect(!model.snapshot.isSpoofing)
            #expect(Array(sessions.auditLog.suffix(3).map(\.event)) == expectedTail)
            #expect(defaults.object(forKey: LocationSpoofing.spoofingDefaultsKey) == nil)
        }

        @Test("As the session expires, the timer firing, the host is told nil, audited before sessionEnded(.expired)")
        func revertsAsSessionExpires() throws {
            let suite = "LocationSpoofingReceiverTests-\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let directory = FileManager.default.temporaryDirectory.appending(path: "LocationSpoofingReceiverTests-\(UUID().uuidString)")
            let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
            #expect(layout.create())
            let payloads: [(String, Data)] = try [
                (sessionsID, TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 3600))),
                (spoofingID, TransportMessage.payload(LocationSpoofing.Command.spoof(paris)))
            ]
            for (index, (id, payload)) in payloads.enumerated() {
                let document = StoreDocument(TransportMessage(kind: .command, pluginID: id, payload: payload))
                try layout.write(document.encoded(), to: layout.commands.appending(path: "\(index).json"))
            }
            let clock = MovableClock(Self.now)
            let timer = ManualTimer()
            let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: clock, timer: timer)
            let observer = SpoofingObserver()
            let model = LocationSpoofing(sessions: sessions, defaults: defaults, now: { clock.now }, spoofingDidChange: observer.spoofingDidChange)
            let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
            sut.enable(.locationSpoofing(model))
            try sut.start()
            defer { sut.stop() }
            let expectedTold: [LocationCoordinate?] = [paris, nil]
            let expectedTail: [DebugDrawerAuditEntry.Event] = [.changeReverted, .sessionEnded(.expired)]

            clock.set(Self.now.addingTimeInterval(300))
            timer.fireNow()

            #expect(observer.told == expectedTold)
            #expect(!model.snapshot.isSpoofing)
            #expect(!sessions.snapshot.isActive)
            #expect(Array(sessions.auditLog.suffix(2).map(\.event)) == expectedTail)
        }

        @Test("The capability's gate turning off ends the spoof at once while the session goes on; the receiver's ends the session")
        func revertsAtGateOff() throws {
            let suite = "LocationSpoofingReceiverTests-\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let directory = FileManager.default.temporaryDirectory.appending(path: "LocationSpoofingReceiverTests-\(UUID().uuidString)")
            let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
            #expect(layout.create())
            let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: MovableClock(Self.now), timer: ManualTimer())
            let observer = SpoofingObserver()
            let model = LocationSpoofing(sessions: sessions, defaults: defaults, now: { Self.now }, spoofingDidChange: observer.spoofingDidChange)
            let capabilityGate = Gate()
            let receiverGate = Gate()
            let sut = DebugDrawerReceiver(directory: directory, sessions: sessions) { receiverGate.isOpen }
            sut.enable(.locationSpoofing(model)) { capabilityGate.isOpen }
            try sut.start()
            defer { sut.stop() }
            sessions.perform(.open(duration: 60))

            /// Leaves a spoof to Paris in the store and has the receiver perform it.
            func spoofParis(_ name: String) throws {
                let payload = try TransportMessage.payload(LocationSpoofing.Command.spoof(paris))
                let document = StoreDocument(TransportMessage(kind: .command, pluginID: spoofingID, payload: payload))
                try layout.write(document.encoded(), to: layout.commands.appending(path: "\(name).json"))
                sut.reevaluateGates()
            }
            try spoofParis("0")
            let firstSpoof = model.isSpoofing
            capabilityGate.isOpen = false
            sut.reevaluateGates()
            let afterCapabilityGate = (model.isSpoofing, sessions.snapshot.isActive)
            capabilityGate.isOpen = true
            try spoofParis("1")
            let secondSpoof = model.isSpoofing
            receiverGate.isOpen = false
            let expectedTold: [LocationCoordinate?] = [paris, nil, paris, nil]

            sut.reevaluateGates()

            #expect(firstSpoof)
            #expect(afterCapabilityGate == (false, true))
            #expect(secondSpoof)
            #expect(!model.isSpoofing)
            #expect(!sessions.snapshot.isActive)
            #expect(observer.told == expectedTold)
            #expect(sessions.auditLog.last?.event == .sessionEnded(.disabledByHost))
        }

        @Test("A coordinate off the Earth, or a spoof without one, is refused malformedCommand and the host hears nothing")
        func malformedSpoofsRefused() throws {
            let suite = "LocationSpoofingReceiverTests-\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let directory = FileManager.default.temporaryDirectory.appending(path: "LocationSpoofingReceiverTests-\(UUID().uuidString)")
            let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
            #expect(layout.create())
            let payloads: [(String, Data)] = try [
                (sessionsID, TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 60))),
                (spoofingID, TransportMessage.payload(LocationSpoofing.Command.spoof(LocationCoordinate(latitude: 91, longitude: 0)))),
                (spoofingID, TransportMessage.payload(LocationSpoofing.Command.spoof(LocationCoordinate(latitude: 0, longitude: 181)))),
                (spoofingID, Data(#"{"spoof":{}}"#.utf8)),
                (spoofingID, Data(#"{"spoof":{"_0":{"latitude":48.8566}}}"#.utf8))
            ]
            for (index, (id, payload)) in payloads.enumerated() {
                let document = StoreDocument(TransportMessage(kind: .command, pluginID: id, payload: payload))
                try layout.write(document.encoded(), to: layout.commands.appending(path: "\(index).json"))
            }
            let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: MovableClock(Self.now), timer: ManualTimer())
            let observer = SpoofingObserver()
            let model = LocationSpoofing(sessions: sessions, defaults: defaults, now: { Self.now }, spoofingDidChange: observer.spoofingDidChange)
            let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
            sut.enable(.locationSpoofing(model))
            let expected = Array(repeating: DebugDrawerAuditEntry.Event.commandRefused(.malformedCommand), count: 4)

            try sut.start()
            defer { sut.stop() }

            #expect(sessions.auditLog.filter { $0.capability == spoofingID }.map(\.event) == expected)
            #expect(observer.told.isEmpty)
            #expect(!model.isSpoofing)
        }

        @Test("Until the host enables it, a spoof is refused unknownCapability in an open session; nothing is served or spoofed")
        func offUnlessEnabled() throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: "LocationSpoofingReceiverTests-\(UUID().uuidString)")
            let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
            #expect(layout.create())
            let payloads: [(String, Data)] = try [
                (sessionsID, TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 60))),
                (spoofingID, TransportMessage.payload(LocationSpoofing.Command.spoof(paris)))
            ]
            for (index, (id, payload)) in payloads.enumerated() {
                let document = StoreDocument(TransportMessage(kind: .command, pluginID: id, payload: payload))
                try layout.write(document.encoded(), to: layout.commands.appending(path: "\(index).json"))
            }
            let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: MovableClock(Self.now), timer: ManualTimer())
            let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
            let flagSuite = "LocationSpoofingReceiverTests.flags.\(UUID().uuidString)"
            let flagDefaults = try #require(UserDefaults(suiteName: flagSuite))
            defer { flagDefaults.removePersistentDomain(forName: flagSuite) }
            sut.enable(.featureFlagOverrides(DebugDrawerFeatureFlagOverrides(adapter: EmptyFlagAdapter(), defaults: flagDefaults)))

            try sut.start()
            defer { sut.stop() }

            let session = try #require(sessions.snapshot.session)
            let expectedEntry = DebugDrawerAuditEntry(
                date: Self.now, sessionID: session.id, capability: spoofingID, event: .commandRefused(.unknownCapability)
            )
            #expect(sessions.auditLog.last == expectedEntry)
            #expect(sut.enabledCapabilities == [flagsID])
            #expect(!FileManager.default.fileExists(atPath: layout.snapshotFile(for: spoofingID).path))
        }

        @Test("With a grant policy a spoof needs a grant listing the capability: none opens no session, another's is capabilityNotGranted")
        func grantRequiredUnderPolicy() throws {
            let suite = "LocationSpoofingReceiverTests-\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let directory = FileManager.default.temporaryDirectory.appending(path: "LocationSpoofingReceiverTests-\(UUID().uuidString)")
            let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
            #expect(layout.create())
            let policy = DebugDrawerGrantPolicy(
                verifier: ListingGrantVerifier(audience: "com.example.MyApp", date: Self.now), audience: "com.example.MyApp"
            )
            let sessions = DebugDrawerSessions(
                maximumDuration: 300, auditCapacity: 100, grantPolicy: policy, clock: MovableClock(Self.now), timer: ManualTimer()
            )
            let observer = SpoofingObserver()
            let model = LocationSpoofing(sessions: sessions, defaults: defaults, now: { Self.now }, spoofingDidChange: observer.spoofingDidChange)
            let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
            sut.enable(.locationSpoofing(model))
            let flagSuite = "LocationSpoofingReceiverTests.flags.\(UUID().uuidString)"
            let flagDefaults = try #require(UserDefaults(suiteName: flagSuite))
            defer { flagDefaults.removePersistentDomain(forName: flagSuite) }
            sut.enable(.featureFlagOverrides(DebugDrawerFeatureFlagOverrides(adapter: EmptyFlagAdapter(), defaults: flagDefaults)))
            try sut.start()
            defer { sut.stop() }
            var outcomes: [DebugDrawerAuditEntry.Event] = []

            /// Leaves a spoof to Paris in the store, has the receiver perform it, and keeps the last
            /// audit entry.
            func spoofParis(_ name: String) throws {
                let payload = try TransportMessage.payload(LocationSpoofing.Command.spoof(paris))
                let document = StoreDocument(TransportMessage(kind: .command, pluginID: spoofingID, payload: payload))
                try layout.write(document.encoded(), to: layout.commands.appending(path: "\(name).json"))
                sut.reevaluateGates()
                if let last = sessions.auditLog.last {
                    outcomes.append(last.event)
                }
            }
            sessions.perform(.open(duration: 60))
            try spoofParis("0")
            sessions.perform(.open(duration: 60, grant: flagsID))
            try spoofParis("1")
            let spoofedWithFlagsGrant = (model.isSpoofing, observer.told)
            sessions.perform(.end)
            sessions.perform(.open(duration: 60, grant: "\(flagsID),\(spoofingID)"))

            try spoofParis("2")

            #expect(outcomes == [.commandRefused(.noActiveSession), .commandRefused(.capabilityNotGranted), .commandApplied])
            #expect(spoofedWithFlagsGrant.0 == false)
            #expect(spoofedWithFlagsGrant.1.isEmpty)
            #expect(observer.told == [paris])
            #expect(model.isSpoofing)
        }

        @Test("requiringGrant() refuses a spoof grantMissing in a session without a grant, in a receiver with no policy")
        func requiringGrantWithoutPolicy() throws {
            let suite = "LocationSpoofingReceiverTests-\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let directory = FileManager.default.temporaryDirectory.appending(path: "LocationSpoofingReceiverTests-\(UUID().uuidString)")
            let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
            #expect(layout.create())
            let payloads: [(String, Data)] = try [
                (sessionsID, TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 60))),
                (spoofingID, TransportMessage.payload(LocationSpoofing.Command.spoof(paris)))
            ]
            for (index, (id, payload)) in payloads.enumerated() {
                let document = StoreDocument(TransportMessage(kind: .command, pluginID: id, payload: payload))
                try layout.write(document.encoded(), to: layout.commands.appending(path: "\(index).json"))
            }
            let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: MovableClock(Self.now), timer: ManualTimer())
            let observer = SpoofingObserver()
            let model = LocationSpoofing(sessions: sessions, defaults: defaults, now: { Self.now }, spoofingDidChange: observer.spoofingDidChange)
            let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
            sut.enable(.locationSpoofing(model).requiringGrant())

            try sut.start()
            defer { sut.stop() }

            #expect(sessions.auditLog.last?.event == .commandRefused(.grantMissing))
            #expect(observer.told.isEmpty)
            #expect(!model.isSpoofing)
        }

        @Test("A spoof a launch was killed in is told over, once, as the next launch makes the capability, before any session")
        func spoofLeftByKillIsEndedAtLaunch() throws {
            let suite = "LocationSpoofingReceiverTests-\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let directory = FileManager.default.temporaryDirectory.appending(path: "LocationSpoofingReceiverTests-\(UUID().uuidString)")
            let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
            #expect(layout.create())
            let payload = try TransportMessage.payload(LocationSpoofing.Command.spoof(paris))
            try layout.write(
                StoreDocument(TransportMessage(kind: .command, pluginID: spoofingID, payload: payload)).encoded(),
                to: layout.commands.appending(path: "0.json")
            )
            let killedSessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: MovableClock(Self.now), timer: ManualTimer())
            let killedObserver = SpoofingObserver()
            let killedLaunch = DebugDrawerReceiver(directory: directory, sessions: killedSessions)
            killedLaunch.enable(.locationSpoofing(LocationSpoofing(
                sessions: killedSessions, defaults: defaults, now: { Self.now }, spoofingDidChange: killedObserver.spoofingDidChange
            )))
            killedSessions.perform(.open(duration: 60))
            try killedLaunch.start()
            // The app is killed with the session open: nothing ends it, so its revert never runs.
            killedLaunch.stop()
            // The next launch: a new process, with new sessions and a model of its own.
            let nextSessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: MovableClock(Self.now), timer: ManualTimer())
            let nextObserver = SpoofingObserver()
            let model = LocationSpoofing(
                sessions: nextSessions, defaults: defaults, now: { Self.now }, spoofingDidChange: nextObserver.spoofingDidChange
            )
            let flaggedAtLaunch = defaults.bool(forKey: LocationSpoofing.spoofingDefaultsKey)
            let expectedTold: [LocationCoordinate?] = [nil]

            _ = DebugDrawerReceiverCapability.locationSpoofing(model)
            _ = DebugDrawerReceiverCapability.locationSpoofing(model)

            #expect(killedObserver.told == [paris])
            #expect(flaggedAtLaunch)
            #expect(nextObserver.told == expectedTold)
            #expect(!model.isSpoofing)
            #expect(defaults.object(forKey: LocationSpoofing.spoofingDefaultsKey) == nil)
        }

        @Test("A launch that follows a clean one tells the host nothing as the capability is made")
        func cleanLaunchTellsNothing() throws {
            let suite = "LocationSpoofingReceiverTests-\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: MovableClock(Self.now), timer: ManualTimer())
            let observer = SpoofingObserver()
            let model = LocationSpoofing(sessions: sessions, defaults: defaults, now: { Self.now }, spoofingDidChange: observer.spoofingDidChange)

            _ = DebugDrawerReceiverCapability.locationSpoofing(model)

            #expect(observer.told.isEmpty)
            #expect(!model.isSpoofing)
        }
    }
#endif
