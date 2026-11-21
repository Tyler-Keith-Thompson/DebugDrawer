#if DEBUG
    import Combine
    @testable import DebugDrawer
    @testable import DebugDrawerReceiver
    import Foundation
    import Testing
    #if os(macOS)
        import AppKit
    #elseif os(watchOS)
        import WatchKit
    #elseif canImport(UIKit)
        import UIKit
    #endif

    /// A session-scoped capability: a log level a sidecar elevates, which `reset` puts back.
    @MainActor
    private final class LogLevelModel: DebugDrawerPluginModel {
        struct Snapshot: Codable, Equatable, Sendable {
            var level = "info"
        }

        enum Command: Codable, Equatable, Sendable {
            case set(String)
            case reset
        }

        @Published private(set) var snapshot = Snapshot()
        private(set) var resets = 0

        func perform(_ command: Command) {
            switch command {
            case let .set(level): snapshot.level = level
            case .reset:
                resets += 1
                snapshot.level = "info"
            }
        }
    }

    /// A persistent capability: feature flag overrides a tester keeps.
    @MainActor
    private final class FlagModel: DebugDrawerPluginModel {
        struct Snapshot: Codable, Equatable, Sendable {
            var overrides: [String: Bool] = [:]
        }

        enum Command: Codable, Equatable, Sendable {
            case override(String, Bool)
            case clear
        }

        @Published private(set) var snapshot = Snapshot()

        func perform(_ command: Command) {
            switch command {
            case let .override(flag, value): snapshot.overrides[flag] = value
            case .clear: snapshot.overrides = [:]
            }
        }
    }

    /// A wall clock the test moves by hand.
    private final class FakeClock: SessionClock {
        var now: Date

        init(_ now: Date) {
            self.now = now
        }
    }

    /// A session timer that records the date it was set for and fires when the test says.
    @MainActor
    private final class FakeTimer: SessionTimer {
        private(set) var scheduled: Date?
        private var handler: (@MainActor () -> Void)?

        func schedule(at date: Date, _ fire: @escaping @MainActor () -> Void) {
            scheduled = date
            handler = fire
        }

        func cancel() {
            scheduled = nil
            handler = nil
        }

        /// Fires the scheduled call, as the run loop would at its date.
        func fire() {
            let handler = handler
            self.handler = nil
            scheduled = nil
            handler?()
        }
    }

    // The sidecar's sessions, driven as a transport drives them: commands arrive at a
    // `RegistrySession` over the store's link (which says no hello), and the registry made with
    // the sessions gates them. Time is a fake clock and expiry a fake timer the test fires, so
    // nothing waits.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct SessionTests {
        private static let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        private let sessionsID = DebugDrawerSessions.pluginID

        @Test("A command to a capability while no session is open is refused, changes nothing, and is audited as refused")
        func refusedWithoutSession() throws {
            let clock = FakeClock(Self.start)
            let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: clock, timer: FakeTimer())
            let registry = DebugDrawerModelRegistry(sessions: sessions)
            let logLevels = LogLevelModel()
            registry.register(logLevels, id: "LogLevels", scope: .session(revertWith: .reset))
            let sut = RegistrySession(registry: registry, link: .store) { _ in }
            let expectedLog = [
                DebugDrawerAuditEntry(date: Self.start, sessionID: nil, capability: "LogLevels", event: .commandRefused(.noActiveSession))
            ]

            try sut.receive(TransportMessage(
                kind: .command, pluginID: "LogLevels", payload: TransportMessage.payload(LogLevelModel.Command.set("debug"))
            ))

            #expect(logLevels.snapshot == LogLevelModel.Snapshot())
            #expect(sessions.snapshot == .inactive)
            #expect(sessions.auditLog == expectedLog)
        }

        @Test("Once a session ends, by the sidecar or the host, or expires, commands are refused again", arguments: ["sidecar", "host", "expiry"])
        func refusedAfterSessionEnds(ending: String) throws {
            let clock = FakeClock(Self.start)
            let timer = FakeTimer()
            let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: clock, timer: timer)
            let registry = DebugDrawerModelRegistry(sessions: sessions)
            let flags = FlagModel()
            registry.register(flags, id: "Flags", scope: .persistent)
            let sut = RegistrySession(registry: registry, link: .store) { _ in }
            let expectedFlags = FlagModel.Snapshot(overrides: ["checkout": true])

            try sut.receive(TransportMessage(
                kind: .command, pluginID: sessionsID, payload: TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 60))
            ))
            try sut.receive(TransportMessage(
                kind: .command, pluginID: "Flags", payload: TransportMessage.payload(FlagModel.Command.override("checkout", true))
            ))
            clock.now = Self.start.addingTimeInterval(60)
            switch ending {
            case "sidecar":
                try sut.receive(TransportMessage(
                    kind: .command, pluginID: sessionsID, payload: TransportMessage.payload(DebugDrawerSessionCommand.end)
                ))
            case "host": sessions.end()
            default: timer.fire()
            }
            try sut.receive(TransportMessage(
                kind: .command, pluginID: "Flags", payload: TransportMessage.payload(FlagModel.Command.override("search", true))
            ))

            #expect(flags.snapshot == expectedFlags)
            #expect(sessions.snapshot == .inactive)
            #expect(sessions.auditLog.last?.event == .commandRefused(.noActiveSession))
            #expect(sessions.auditLog.last?.sessionID == nil)
        }

        @Test("Every applied command is in the audit log with the time it was applied, its capability and its session")
        func appliedCommandsAudited() throws {
            let clock = FakeClock(Self.start)
            let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: clock, timer: FakeTimer())
            let registry = DebugDrawerModelRegistry(sessions: sessions)
            registry.register(LogLevelModel(), id: "LogLevels", scope: .session(revertWith: .reset))
            registry.register(FlagModel(), id: "Flags", scope: .persistent)
            let sut = RegistrySession(registry: registry, link: .store) { _ in }

            try sut.receive(TransportMessage(
                kind: .command, pluginID: sessionsID, payload: TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 120))
            ))
            let session = try #require(sessions.snapshot.session)
            clock.now = Self.start.addingTimeInterval(5)
            try sut.receive(TransportMessage(
                kind: .command, pluginID: "LogLevels", payload: TransportMessage.payload(LogLevelModel.Command.set("debug"))
            ))
            clock.now = Self.start.addingTimeInterval(9)
            try sut.receive(TransportMessage(
                kind: .command, pluginID: "Flags", payload: TransportMessage.payload(FlagModel.Command.override("checkout", true))
            ))
            let expectedLog = [
                DebugDrawerAuditEntry(
                    date: Self.start, sessionID: session.id, capability: sessionsID,
                    event: .sessionOpened(expires: Self.start.addingTimeInterval(120))
                ),
                DebugDrawerAuditEntry(date: Self.start.addingTimeInterval(5), sessionID: session.id, capability: "LogLevels", event: .commandApplied),
                DebugDrawerAuditEntry(date: Self.start.addingTimeInterval(9), sessionID: session.id, capability: "Flags", event: .commandApplied)
            ]

            let actual = sessions.auditLog

            #expect(actual == expectedLog)
        }

        @Test(
            "Ending a session, by the sidecar or the host, reverts each session-scoped change once and keeps persistent ones",
            arguments: ["sidecar", "host"]
        )
        func endRevertsSessionScopedChanges(ending: String) throws {
            let clock = FakeClock(Self.start)
            let timer = FakeTimer()
            let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: clock, timer: timer)
            let registry = DebugDrawerModelRegistry(sessions: sessions)
            let logLevels = LogLevelModel()
            let flags = FlagModel()
            registry.register(logLevels, id: "LogLevels", scope: .session(revertWith: .reset))
            registry.register(flags, id: "Flags", scope: .persistent)
            let sut = RegistrySession(registry: registry, link: .store) { _ in }
            let expectedFlags = FlagModel.Snapshot(overrides: ["checkout": true])

            try sut.receive(TransportMessage(
                kind: .command, pluginID: sessionsID, payload: TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 120))
            ))
            let session = try #require(sessions.snapshot.session)
            try sut.receive(TransportMessage(
                kind: .command, pluginID: "LogLevels", payload: TransportMessage.payload(LogLevelModel.Command.set("debug"))
            ))
            try sut.receive(TransportMessage(
                kind: .command, pluginID: "LogLevels", payload: TransportMessage.payload(LogLevelModel.Command.set("trace"))
            ))
            try sut.receive(TransportMessage(
                kind: .command, pluginID: "Flags", payload: TransportMessage.payload(FlagModel.Command.override("checkout", true))
            ))
            let duringSession = logLevels.snapshot.level
            clock.now = Self.start.addingTimeInterval(30)
            if ending == "sidecar" {
                try sut.receive(TransportMessage(
                    kind: .command, pluginID: sessionsID, payload: TransportMessage.payload(DebugDrawerSessionCommand.end)
                ))
            } else {
                sessions.end()
            }
            let expectedEnd = [
                DebugDrawerAuditEntry(
                    date: Self.start.addingTimeInterval(30), sessionID: session.id, capability: "LogLevels", event: .changeReverted
                ),
                DebugDrawerAuditEntry(
                    date: Self.start.addingTimeInterval(30), sessionID: session.id, capability: sessionsID, event: .sessionEnded(.ended)
                )
            ]

            #expect(duringSession == "trace")
            #expect(logLevels.snapshot == LogLevelModel.Snapshot())
            #expect(logLevels.resets == 1)
            #expect(flags.snapshot == expectedFlags)
            #expect(Array(sessions.auditLog.suffix(2)) == expectedEnd)
            #expect(timer.scheduled == nil)
        }

        @Test("When the timer fires at the expiry, the session expires and its session-scoped changes revert")
        func expiryRevertsSessionScopedChanges() throws {
            let clock = FakeClock(Self.start)
            let timer = FakeTimer()
            let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: clock, timer: timer)
            let registry = DebugDrawerModelRegistry(sessions: sessions)
            let logLevels = LogLevelModel()
            registry.register(logLevels, id: "LogLevels", scope: .session(revertWith: .reset))
            let sut = RegistrySession(registry: registry, link: .store) { _ in }

            try sut.receive(TransportMessage(
                kind: .command, pluginID: sessionsID, payload: TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 45))
            ))
            let session = try #require(sessions.snapshot.session)
            try sut.receive(TransportMessage(
                kind: .command, pluginID: "LogLevels", payload: TransportMessage.payload(LogLevelModel.Command.set("debug"))
            ))
            let duringSession = logLevels.snapshot.level
            clock.now = Self.start.addingTimeInterval(45)
            timer.fire()
            let expectedEnd = [
                DebugDrawerAuditEntry(
                    date: Self.start.addingTimeInterval(45), sessionID: session.id, capability: "LogLevels", event: .changeReverted
                ),
                DebugDrawerAuditEntry(
                    date: Self.start.addingTimeInterval(45), sessionID: session.id, capability: sessionsID, event: .sessionEnded(.expired)
                )
            ]

            #expect(duringSession == "debug")
            #expect(logLevels.snapshot == LogLevelModel.Snapshot())
            #expect(sessions.snapshot == .inactive)
            #expect(Array(sessions.auditLog.suffix(2)) == expectedEnd)
        }

        @Test("A command after the expiry, before a late timer fires, expires the session first, reverting it, and is refused")
        func lateTimer() throws {
            let clock = FakeClock(Self.start)
            let timer = FakeTimer()
            let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: clock, timer: timer)
            let registry = DebugDrawerModelRegistry(sessions: sessions)
            let logLevels = LogLevelModel()
            registry.register(logLevels, id: "LogLevels", scope: .session(revertWith: .reset))
            let sut = RegistrySession(registry: registry, link: .store) { _ in }
            let expectedEvents: [DebugDrawerAuditEntry.Event] = [
                .sessionOpened(expires: Self.start.addingTimeInterval(45)),
                .commandApplied,
                .changeReverted,
                .sessionEnded(.expired),
                .commandRefused(.noActiveSession)
            ]

            try sut.receive(TransportMessage(
                kind: .command, pluginID: sessionsID, payload: TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 45))
            ))
            try sut.receive(TransportMessage(
                kind: .command, pluginID: "LogLevels", payload: TransportMessage.payload(LogLevelModel.Command.set("debug"))
            ))
            clock.now = Self.start.addingTimeInterval(46)
            try sut.receive(TransportMessage(
                kind: .command, pluginID: "LogLevels", payload: TransportMessage.payload(LogLevelModel.Command.set("trace"))
            ))
            timer.fire()

            #expect(logLevels.snapshot == LogLevelModel.Snapshot())
            #expect(sessions.snapshot == .inactive)
            #expect(sessions.auditLog.map(\.event) == expectedEvents)
        }

        @Test("A session lasts the duration asked for, at most the host's maximum, and the timer is set for its expiry", arguments: [
            (10.0, 10.0), (300.0, 300.0), (3600.0, 300.0), (Double.infinity, 300.0)
        ])
        func durationIsCapped(asked: TimeInterval, expectedDuration: TimeInterval) {
            let timer = FakeTimer()
            let sut = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: FakeClock(Self.start), timer: timer)
            let expected = Self.start.addingTimeInterval(expectedDuration)

            sut.perform(.open(duration: asked))

            #expect(sut.snapshot.session?.opened == Self.start)
            #expect(sut.snapshot.session?.expires == expected)
            #expect(timer.scheduled == expected)
        }

        @Test(
            "A session asked for a duration that isn't positive, or under a maximum that isn't, doesn't open and is audited as refused",
            arguments: [
            (0.0, 300.0), (-5.0, 300.0), (Double.nan, 300.0), (60.0, 0.0)
        ])
        func invalidDurationRefused(asked: TimeInterval, maximum: TimeInterval) {
            let timer = FakeTimer()
            let sut = DebugDrawerSessions(maximumDuration: maximum, auditCapacity: 100, clock: FakeClock(Self.start), timer: timer)
            let expectedLog = [
                DebugDrawerAuditEntry(date: Self.start, sessionID: nil, capability: sessionsID, event: .commandRefused(.invalidDuration))
            ]

            sut.perform(.open(duration: asked))

            #expect(sut.snapshot == .inactive)
            #expect(timer.scheduled == nil)
            #expect(sut.auditLog == expectedLog)
        }

        @Test("Opening a session while one is open is refused and leaves the open one, and its expiry, as they were")
        func openWhileActiveRefused() throws {
            let clock = FakeClock(Self.start)
            let timer = FakeTimer()
            let sut = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: clock, timer: timer)

            sut.perform(.open(duration: 60))
            let first = try #require(sut.snapshot.session)
            clock.now = Self.start.addingTimeInterval(50)
            sut.perform(.open(duration: 300))

            #expect(sut.snapshot == .active(first))
            #expect(timer.scheduled == first.expires)
            #expect(sut.auditLog.last == DebugDrawerAuditEntry(
                date: Self.start.addingTimeInterval(50), sessionID: first.id, capability: sessionsID,
                event: .commandRefused(.sessionAlreadyActive)
            ))
        }

        @Test("Under sessions, a model registered without a scope serves its snapshots, and its commands are refused")
        func undeclaredScopeRefused() async throws {
            let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: FakeClock(Self.start), timer: FakeTimer())
            let registry = DebugDrawerModelRegistry(sessions: sessions)
            let flags = FlagModel()
            registry.register(flags, id: "Flags")
            let (outbox, sent) = AsyncStream<TransportMessage>.makeStream()
            let sut = RegistrySession(registry: registry, link: .store) { sent.yield($0) }
            var viewer = outbox.makeAsyncIterator()

            sut.receive(TransportMessage(kind: .subscribe, pluginID: "Flags"))
            let served = await viewer.next()
            try sut.receive(TransportMessage(
                kind: .command, pluginID: sessionsID, payload: TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 60))
            ))
            try sut.receive(TransportMessage(
                kind: .command, pluginID: "Flags", payload: TransportMessage.payload(FlagModel.Command.override("checkout", true))
            ))

            #expect(served?.kind == .snapshot)
            #expect(served?.pluginID == "Flags")
            #expect(flags.snapshot == FlagModel.Snapshot())
            #expect(sessions.auditLog.last?.event == .commandRefused(.undeclaredScope))
            #expect(sessions.auditLog.last?.capability == "Flags")
            sut.close()
        }

        @Test("Within a session, a command to no registered model, or one that doesn't decode, is refused and audited")
        func unknownAndMalformedRefused() throws {
            let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: FakeClock(Self.start), timer: FakeTimer())
            let registry = DebugDrawerModelRegistry(sessions: sessions)
            let logLevels = LogLevelModel()
            registry.register(logLevels, id: "LogLevels", scope: .session(revertWith: .reset))
            let sut = RegistrySession(registry: registry, link: .store) { _ in }
            let expectedEvents: [DebugDrawerAuditEntry.Event] = [.commandRefused(.unknownCapability), .commandRefused(.malformedCommand)]

            try sut.receive(TransportMessage(
                kind: .command, pluginID: sessionsID, payload: TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 60))
            ))
            try sut.receive(TransportMessage(kind: .command, pluginID: "Missing", payload: TransportMessage.payload(LogLevelModel.Command.reset)))
            sut.receive(TransportMessage(kind: .command, pluginID: "LogLevels", payload: Data("{\"shout\":{}}".utf8)))

            #expect(Array(sessions.auditLog.suffix(2).map(\.event)) == expectedEvents)
            #expect(sessions.auditLog.suffix(2).map(\.capability) == ["Missing", "LogLevels"])
            #expect(logLevels.resets == 0)
        }

        @Test("Over the socket, a command refused outside a session is acknowledged; sent again through the store, it isn't applied in a session")
        func refusalIsAcknowledgedAndFinal() throws {
            let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: FakeClock(Self.start), timer: FakeTimer())
            let registry = DebugDrawerModelRegistry(sessions: sessions)
            let logLevels = LogLevelModel()
            registry.register(logLevels, id: "LogLevels", scope: .session(revertWith: .reset))
            var socketSent: [TransportMessage] = []
            let socketSession = RegistrySession(registry: registry, link: .stream) { socketSent.append($0) }
            let storeSession = RegistrySession(registry: registry, link: .store) { _ in }
            let id = UUID()
            let elevate = try TransportMessage(
                kind: .command, pluginID: "LogLevels", payload: TransportMessage.payload(LogLevelModel.Command.set("debug")), commandID: id
            )
            let expectedEvents: [DebugDrawerAuditEntry.Event] = [
                .commandRefused(.noActiveSession), .sessionOpened(expires: Self.start.addingTimeInterval(60))
            ]

            socketSession.receive(.hello(.current))
            socketSession.receive(elevate)
            socketSession.close()
            storeSession.receive(.hello(.current))
            try storeSession.receive(TransportMessage(
                kind: .command, pluginID: sessionsID, payload: TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 60)),
                commandID: UUID()
            ))
            storeSession.receive(elevate)

            #expect(socketSent.map(\.kind) == [.hello, .acknowledgement])
            #expect(socketSent.last?.commandID == id)
            #expect(logLevels.snapshot == LogLevelModel.Snapshot())
            #expect(sessions.auditLog.map(\.event) == expectedEvents)
        }

        @Test("Within a session, a command delivered over the socket and again through the store is applied and audited once")
        func appliedOnceAcrossChannels() throws {
            let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: FakeClock(Self.start), timer: FakeTimer())
            let registry = DebugDrawerModelRegistry(sessions: sessions)
            let flags = FlagModel()
            registry.register(flags, id: "Flags", scope: .persistent)
            let socketSession = RegistrySession(registry: registry, link: .stream) { _ in }
            let storeSession = RegistrySession(registry: registry, link: .store) { _ in }
            let override = try TransportMessage(
                kind: .command, pluginID: "Flags", payload: TransportMessage.payload(FlagModel.Command.override("checkout", true)), commandID: UUID()
            )
            let expectedEvents: [DebugDrawerAuditEntry.Event] = [.sessionOpened(expires: Self.start.addingTimeInterval(60)), .commandApplied]

            socketSession.receive(.hello(.current))
            try socketSession.receive(TransportMessage(
                kind: .command, pluginID: sessionsID, payload: TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 60)),
                commandID: UUID()
            ))
            socketSession.receive(override)
            socketSession.close()
            storeSession.receive(.hello(.current))
            storeSession.receive(override)

            #expect(flags.snapshot.overrides == ["checkout": true])
            #expect(sessions.auditLog.map(\.event) == expectedEvents)
        }

        @Test("A registry made without sessions performs every command, as it did before sessions")
        func registryWithoutSessions() throws {
            let registry = DebugDrawerModelRegistry()
            let flags = FlagModel()
            registry.register(flags, id: "Flags")
            let sut = RegistrySession(registry: registry, link: .store) { _ in }
            let expected = FlagModel.Snapshot(overrides: ["checkout": true])

            try sut.receive(TransportMessage(
                kind: .command, pluginID: "Flags", payload: TransportMessage.payload(FlagModel.Command.override("checkout", true))
            ))

            #expect(flags.snapshot == expected)
        }

        @Test("The audit log keeps the newest entries up to its capacity, and auditEntries publishes every one", arguments: [0, 1, 3])
        func auditLogIsBounded(capacity: Int) {
            let clock = FakeClock(Self.start)
            let sut = DebugDrawerSessions(maximumDuration: 300, auditCapacity: capacity, clock: clock, timer: FakeTimer())
            var published: [DebugDrawerAuditEntry] = []
            let subscription = sut.auditEntries.sink { published.append($0) }

            for second in 0 ..< 5 {
                clock.now = Self.start.addingTimeInterval(TimeInterval(second))
                sut.perform(.open(duration: 0))
            }

            #expect(published.count == 5)
            #expect(sut.auditLog == Array(published.suffix(capacity)))
            subscription.cancel()
        }

        @Test("An audit entry encodes as JSON naming its date, session, capability and event, and nothing a command carried")
        func auditEntryJSON() throws {
            let sessionID = try #require(UUID(uuidString: "6F1C2A4E-1D2B-4C3D-8E9F-0A1B2C3D4E5F"))
            let entry = DebugDrawerAuditEntry(date: Self.start, sessionID: sessionID, capability: "LogLevels", event: .commandApplied)
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            let expected = #"{"capability":"LogLevels","date":800000000,"event":{"commandApplied":{}},"#
                + #""sessionID":"6F1C2A4E-1D2B-4C3D-8E9F-0A1B2C3D4E5F"}"#

            let encoded = try encoder.encode(entry)
            let actual = String(bytes: encoded, encoding: .utf8)

            #expect(actual == expected)
            #expect(try JSONDecoder().decode(DebugDrawerAuditEntry.self, from: encoded) == entry)
        }

        @Test("Over the app-group store, a sidecar opens a session, sees it active, elevates a session-scoped capability, and ends it, reverting it")
        func sidecarOverStore() async throws {
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let registry = DebugDrawerModelRegistry(sessions: sessions)
            let logLevels = LogLevelModel()
            registry.register(logLevels, id: "LogLevels", scope: .session(revertWith: .reset))
            let directory = FileManager.default.temporaryDirectory.appending(path: "SessionTests-\(UUID().uuidString)")
            let server = DebugDrawerAppGroupStoreServer(registry: registry, directory: directory)
            // The test's own center, so its foreground posts wake no other test's server.
            let center = NotificationCenter()
            server.notificationCenter = center
            try server.start()
            let sidecar = try DebugDrawerAppGroupStoreTransport(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
            let session = try await sidecar.connect(
                toPlugin: sessionsID, snapshot: DebugDrawerSessionState.self, command: DebugDrawerSessionCommand.self
            )
            let levels = try await sidecar.connect(toPlugin: "LogLevels", snapshot: LogLevelModel.Snapshot.self, command: LogLevelModel.Command.self)
            #if os(macOS)
                let foreground = NSApplication.willBecomeActiveNotification
            #elseif os(watchOS)
                let foreground = WKApplication.willEnterForegroundNotification
            #else
                let foreground = UIApplication.willEnterForegroundNotification
            #endif
            let expectedEvents: [DebugDrawerAuditEntry.Event] = [
                .commandRefused(.noActiveSession), .commandApplied, .changeReverted, .sessionEnded(.ended)
            ]

            // Each foreground post performs the commands waiting in the store before it returns.
            levels.send(.set("debug"))
            center.post(name: foreground, object: nil)
            let beforeSession = logLevels.snapshot.level
            session.send(.open(duration: 60))
            center.post(name: foreground, object: nil)
            for await state in session.snapshots() where state.isActive {
                break
            }
            levels.send(.set("debug"))
            center.post(name: foreground, object: nil)
            let duringSession = logLevels.snapshot.level
            session.send(.end)
            center.post(name: foreground, object: nil)
            for await state in session.snapshots() where !state.isActive {
                break
            }

            #expect(beforeSession == "info")
            #expect(duringSession == "debug")
            #expect(logLevels.snapshot == LogLevelModel.Snapshot())
            #expect(sessions.auditLog.map(\.event).filter { if case .sessionOpened = $0 { false } else { true } } == expectedEvents)
            server.stop()
        }

        @Test("The production timer calls back once for an expiry that has already passed")
        func runLoopTimerFires() async {
            let sut = RunLoopSessionTimer()

            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                sut.schedule(at: .distantPast) { continuation.resume() }
            }

            #expect(sut.timer?.isValid == false)
        }
    }
#endif
