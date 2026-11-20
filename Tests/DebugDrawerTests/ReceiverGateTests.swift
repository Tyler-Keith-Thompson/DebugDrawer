// The host's kill switch as a sidecar meets it: a real DebugDrawerReceiver serving the app-group
// store, and the sidecar's DebugDrawerAppGroupStoreTransport (a debug-build type) on the same
// directory, opening sessions through the sessions' own model and driving two capabilities of the
// host's. The gates are closures over a value the test flips, as a host's remote configuration
// would; each test waits for the audit entries the receiver records, so nothing waits on time.
#if DEBUG
    import Combine
    import DebugDrawer
    @testable import DebugDrawerReceiver
    import Foundation
    import Testing

    /// A host's remote configuration: one switch the test flips.
    @MainActor
    private final class RemoteSwitch {
        var isOn: Bool

        init(_ isOn: Bool) {
            self.isOn = isOn
        }
    }

    /// A capability of the host's own: a setting a sidecar changes for the session.
    @MainActor
    private final class SettingModel: DebugDrawerPluginModel {
        struct Snapshot: Codable, Equatable, Sendable {
            var value: String
        }

        enum Command: Codable, Equatable, Sendable {
            case set(String)
            case reset
        }

        let initial: String
        @Published private(set) var snapshot: Snapshot

        init(_ initial: String) {
            self.initial = initial
            snapshot = Snapshot(value: initial)
        }

        func perform(_ command: Command) {
            switch command {
            case let .set(value): snapshot.value = value
            case .reset: snapshot.value = initial
            }
        }
    }

    /// The receiver, its sessions, two capabilities and a sidecar connected to the sessions. A
    /// sidecar connects to a capability once its snapshot is served: connecting waits for one.
    @MainActor
    private struct Fixture {
        static let logLevelsID = "MyApp.LogLevels"
        static let themeID = "MyApp.Theme"

        let sessions = DebugDrawerSessions(maximumDuration: 300)
        let logLevels = SettingModel("info")
        let theme = SettingModel("light")
        let layout: AppGroupStoreLayout
        let receiver: DebugDrawerReceiver
        let sidecar: DebugDrawerAppGroupStoreTransport
        let sessionControl: DebugDrawerPluginTransport<DebugDrawerSessionState, DebugDrawerSessionCommand>
        let entries: AsyncStream<DebugDrawerAuditEntry>
        private let subscription: AnyCancellable

        init(receiverGate: RemoteSwitch, themeGate: RemoteSwitch) async throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: "ReceiverGateTests-\(UUID().uuidString)")
            layout = AppGroupStoreLayout(directory: directory)
            receiver = DebugDrawerReceiver(directory: directory, sessions: sessions) { receiverGate.isOn }
            receiver.enable(.model(logLevels, id: Self.logLevelsID, scope: .session(revertWith: .reset)))
            receiver.enable(.model(theme, id: Self.themeID, scope: .session(revertWith: .reset))) { themeGate.isOn }
            let (entries, entry) = AsyncStream<DebugDrawerAuditEntry>.makeStream()
            self.entries = entries
            subscription = sessions.auditEntries.sink { entry.yield($0) }
            try receiver.start()
            sidecar = try DebugDrawerAppGroupStoreTransport(directory: directory)
            sessionControl = try await sidecar.connect(
                toPlugin: DebugDrawerSessions.pluginID, snapshot: DebugDrawerSessionState.self, command: DebugDrawerSessionCommand.self
            )
        }

        /// The sidecar's connection to the capability under `id`, once its snapshot is served.
        func control(_ id: String) async throws -> DebugDrawerPluginTransport<SettingModel.Snapshot, SettingModel.Command> {
            try await sidecar.connect(toPlugin: id, snapshot: SettingModel.Snapshot.self, command: SettingModel.Command.self)
        }

        /// The audit entries recorded from now until one `last` accepts, that one included.
        func entries(until last: (DebugDrawerAuditEntry) -> Bool) async -> [DebugDrawerAuditEntry] {
            var recorded: [DebugDrawerAuditEntry] = []
            for await entry in entries {
                recorded.append(entry)
                if last(entry) { break }
            }
            return recorded
        }

        /// Opens a session from the sidecar and returns its ID.
        func openSession() async throws -> UUID {
            sessionControl.send(.open(duration: 60))
            let opened = await entries { if case .sessionOpened = $0.event { true } else { false } }
            return try #require(opened.last?.sessionID)
        }

        func snapshotExists(_ id: String) -> Bool {
            FileManager.default.fileExists(atPath: layout.snapshotFile(for: id).path)
        }
    }

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct ReceiverGateTests {
        private let sessionsID = DebugDrawerSessions.pluginID
        private let logLevelsID = Fixture.logLevelsID
        private let themeID = Fixture.themeID

        @Test("With the gate off a session can't open, the refusal is audited, only the sessions' snapshot is served; back on, a session opens")
        func gateOffRefusesSessions() async throws {
            let receiverGate = RemoteSwitch(false)
            let sut = try await Fixture(receiverGate: receiverGate, themeGate: RemoteSwitch(true))
            defer { sut.receiver.stop() }
            let expectedRefusal = [DebugDrawerAuditEntry.Event.commandRefused(.receiverDisabled)]

            sut.sessionControl.send(.open(duration: 60))
            let refused = await sut.entries { _ in true }

            #expect(refused.map(\.event) == expectedRefusal)
            #expect(refused.map(\.capability) == [sessionsID])
            #expect(refused.first?.sessionID == nil)
            #expect(sut.sessions.snapshot == .inactive)
            #expect(sut.snapshotExists(sessionsID))
            #expect(!sut.snapshotExists(logLevelsID))
            #expect(!sut.snapshotExists(themeID))

            receiverGate.isOn = true
            sut.receiver.reevaluateGates()
            let session = try await sut.openSession()
            let logLevels = try await sut.control(logLevelsID)

            #expect(sut.sessions.snapshot.session?.id == session)
            #expect(logLevels.snapshot == SettingModel.Snapshot(value: "info"))
        }

        @Test("The gate turned off in a session: the next command is refused, the session ends as disabledByHost, its changes revert")
        func nextCommandEndsSession() async throws {
            let receiverGate = RemoteSwitch(true)
            let sut = try await Fixture(receiverGate: receiverGate, themeGate: RemoteSwitch(true))
            defer { sut.receiver.stop() }
            let logLevels = try await sut.control(logLevelsID)
            let session = try await sut.openSession()
            logLevels.send(.set("debug"))
            _ = await sut.entries { $0.event == .commandApplied }
            #expect(sut.logLevels.snapshot.value == "debug")
            let expectedTail = [
                DebugDrawerAuditEntry(date: .distantPast, sessionID: session, capability: logLevelsID, event: .commandRefused(.receiverDisabled)),
                DebugDrawerAuditEntry(date: .distantPast, sessionID: session, capability: logLevelsID, event: .changeReverted),
                DebugDrawerAuditEntry(date: .distantPast, sessionID: session, capability: sessionsID, event: .sessionEnded(.disabledByHost))
            ]
            var sessionStates = sut.sessionControl.snapshots().makeAsyncIterator()

            receiverGate.isOn = false
            logLevels.send(.set("trace"))
            let tail = await sut.entries { $0.event == .sessionEnded(.disabledByHost) }
            var seenBySidecar = await sessionStates.next()
            while seenBySidecar?.isActive == true {
                seenBySidecar = await sessionStates.next()
            }

            let undated = tail.map { DebugDrawerAuditEntry(date: .distantPast, sessionID: $0.sessionID, capability: $0.capability, event: $0.event) }
            #expect(undated == expectedTail)
            #expect(sut.logLevels.snapshot.value == "info")
            #expect(sut.sessions.snapshot == .inactive)
            #expect(seenBySidecar == .inactive)
            #expect(!sut.snapshotExists(logLevelsID))
        }

        @Test("reevaluateGates() ends the session as the gate turns off, with no command, and a new one opens once it is back on")
        func reevaluateEndsSession() async throws {
            let receiverGate = RemoteSwitch(true)
            let sut = try await Fixture(receiverGate: receiverGate, themeGate: RemoteSwitch(true))
            defer { sut.receiver.stop() }
            let theme = try await sut.control(themeID)
            let first = try await sut.openSession()
            theme.send(.set("dark"))
            _ = await sut.entries { $0.event == .commandApplied }
            let expectedEvents: [DebugDrawerAuditEntry.Event] = [.changeReverted, .sessionEnded(.disabledByHost)]

            receiverGate.isOn = false
            sut.receiver.reevaluateGates()
            let ended = await sut.entries { $0.event == .sessionEnded(.disabledByHost) }

            #expect(ended.map(\.event) == expectedEvents)
            #expect(ended.allSatisfy { $0.sessionID == first })
            #expect(sut.theme.snapshot.value == "light")
            #expect(sut.sessions.snapshot == .inactive)
            #expect(!sut.snapshotExists(themeID))
            #expect(!sut.snapshotExists(logLevelsID))

            receiverGate.isOn = true
            sut.receiver.reevaluateGates()
            let second = try await sut.openSession()

            #expect(second != first)
            #expect(sut.sessions.snapshot.session?.id == second)
        }

        @Test("With one capability's gate off, its commands are refused as capabilityDisabled while the others apply, in the same session")
        func capabilityGateRefuses() async throws {
            let themeGate = RemoteSwitch(true)
            let sut = try await Fixture(receiverGate: RemoteSwitch(true), themeGate: themeGate)
            defer { sut.receiver.stop() }
            let theme = try await sut.control(themeID)
            let logLevels = try await sut.control(logLevelsID)
            let session = try await sut.openSession()
            themeGate.isOn = false

            theme.send(.set("dark"))
            let refused = await sut.entries { _ in true }
            logLevels.send(.set("debug"))
            let applied = await sut.entries { _ in true }

            #expect(refused.map(\.event) == [.commandRefused(.capabilityDisabled)])
            #expect(refused.map(\.capability) == [themeID])
            #expect(refused.first?.sessionID == session)
            #expect(applied.map(\.event) == [.commandApplied])
            #expect(applied.map(\.capability) == [logLevelsID])
            #expect(sut.theme.snapshot.value == "light")
            #expect(sut.logLevels.snapshot.value == "debug")
            #expect(sut.sessions.snapshot.session?.id == session)
            #expect(!sut.snapshotExists(themeID))
            #expect(sut.snapshotExists(logLevelsID))
        }

        @Test("A capability's gate turned off in a session stops it: its change reverts at the next command or reevaluateGates(); the rest goes on")
        func capabilityGateStopsDuringSession() async throws {
            let themeGate = RemoteSwitch(true)
            let sut = try await Fixture(receiverGate: RemoteSwitch(true), themeGate: themeGate)
            defer { sut.receiver.stop() }
            let theme = try await sut.control(themeID)
            let logLevels = try await sut.control(logLevelsID)
            let session = try await sut.openSession()
            theme.send(.set("dark"))
            _ = await sut.entries { $0.event == .commandApplied }
            logLevels.send(.set("debug"))
            _ = await sut.entries { $0.event == .commandApplied }

            // At the next command, to the other capability.
            themeGate.isOn = false
            logLevels.send(.set("trace"))
            let atCommand = await sut.entries { $0.capability == logLevelsID }
            // Then at reevaluateGates(), after it was turned back on and changed again.
            themeGate.isOn = true
            sut.receiver.reevaluateGates()
            theme.send(.set("sepia"))
            _ = await sut.entries { $0.event == .commandApplied }
            themeGate.isOn = false
            sut.receiver.reevaluateGates()
            let atReevaluation = await sut.entries { _ in true }
            theme.send(.set("dark"))
            let refused = await sut.entries { _ in true }

            #expect(atCommand.map(\.capability) == [themeID, logLevelsID])
            #expect(atCommand.map(\.event) == [.changeReverted, .commandApplied])
            #expect(atReevaluation.map(\.capability) == [themeID])
            #expect(atReevaluation.map(\.event) == [.changeReverted])
            #expect(refused.map(\.event) == [.commandRefused(.capabilityDisabled)])
            #expect(sut.theme.snapshot.value == "light")
            #expect(sut.logLevels.snapshot.value == "trace")
            #expect(sut.sessions.snapshot.session?.id == session)
            #expect(!sut.snapshotExists(themeID))
            #expect(sut.snapshotExists(logLevelsID))
        }
    }
#endif
