// The analytics mirror as a sidecar reaches it: a real DebugDrawerReceiver serving the app-group
// store, and the sidecar's DebugDrawerAppGroupStoreTransport (a debug-build type) reading it from
// the same directory, opening and ending sessions through the sessions' own model. Events go through
// the real sink, AnalyticsEvents.record, which every mirror whose session is open hears; SwiftPM
// runs every test target in one process, where another target's tests may record at the same
// time, so each test names its events with a prefix of its own and reads back only those.
#if DEBUG
    import DebugDrawer
    @testable import DebugDrawerAnalytics
    @testable import DebugDrawerReceiver
    import Foundation
    import os
    import Testing

    /// A wall clock the test moves by hand.
    private final class MovableClock: SessionClock, Sendable {
        private let time: OSAllocatedUnfairLock<Date>

        init(_ start: Date) {
            time = OSAllocatedUnfairLock(initialState: start)
        }

        var now: Date {
            time.withLock { $0 }
        }

        func advance(by interval: TimeInterval) {
            time.withLock { $0 += interval }
        }
    }

    /// A session timer that fires when the test says.
    @MainActor
    private final class ManualTimer: SessionTimer {
        private var scheduled: (@MainActor () -> Void)?

        func schedule(at date: Date, _ fire: @escaping @MainActor () -> Void) {
            scheduled = fire
        }

        func cancel() {
            scheduled = nil
        }

        func fire() {
            let fire = scheduled
            scheduled = nil
            fire?()
        }
    }

    @MainActor
    @Suite(.serialized, .timeLimit(.minutes(1)))
    struct AnalyticsMirrorSessionTests {
        @Test("Only the events recorded while a session is open reach the sidecar, in order: none from before it, none after it ends")
        func onlyDuringSessionAfterEnd() async throws {
            let prefix = "end-\(UUID().uuidString)-"
            let directory = FileManager.default.temporaryDirectory.appending(path: "AnalyticsMirrorSessionTests-\(UUID().uuidString)")
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let receiver = DebugDrawerReceiver(directory: directory, sessions: sessions)
            receiver.enable(.analyticsEvents(sessions: sessions))
            try receiver.start()
            defer { receiver.stop() }
            let sidecar = try DebugDrawerAppGroupStoreTransport(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
            let sessionControl = try await sidecar.connect(
                toPlugin: DebugDrawerSessions.pluginID, snapshot: DebugDrawerSessionState.self, command: DebugDrawerSessionCommand.self
            )
            func ours(_ snapshot: AnalyticsEventsMirror.Snapshot) -> [String] {
                snapshot.events.map(\.name).filter { $0.hasPrefix(prefix) }
            }
            let expectedFirst = ["\(prefix)during-1", "\(prefix)during-2", "\(prefix)during-3"]
            let expectedSecond = ["\(prefix)second-session"]

            AnalyticsEvents.record("\(prefix)before-1", properties: ["step": 1])
            AnalyticsEvents.record("\(prefix)before-2")
            sessionControl.send(.open(duration: 60))
            // Served once the session is open.
            let events = try await sidecar.connect(
                toPlugin: AnalyticsEventsMirror.pluginID, snapshot: AnalyticsEventsMirror.Snapshot.self, command: AnalyticsEventsMirror.Command.self
            )
            var arrivals = events.snapshots().makeAsyncIterator()
            var opened: [AnalyticsEventsMirror.Snapshot] = []
            while let snapshot = await arrivals.next() {
                opened.append(snapshot)
                if snapshot.sessionID != nil { break }
            }
            AnalyticsEvents.record("\(prefix)during-1", properties: ["step": 1])
            AnalyticsEvents.record("\(prefix)during-2", properties: ["step": 2])
            AnalyticsEvents.record("\(prefix)during-3", properties: ["step": 3], source: "Segment")
            var during: [AnalyticsEventsMirror.Snapshot] = []
            while let snapshot = await arrivals.next() {
                during.append(snapshot)
                if ours(snapshot).count >= 3 { break }
            }
            let firstSession = try #require(opened.last?.sessionID)
            sessionControl.send(.end)
            for await state in sessionControl.snapshots() where !state.isActive {
                break
            }
            let snapshotFile = AppGroupStoreLayout(directory: receiver.appDirectory).snapshotFile(for: AnalyticsEventsMirror.pluginID)
            let servedAfterEnd = FileManager.default.fileExists(atPath: snapshotFile.path)
            AnalyticsEvents.record("\(prefix)after-1")
            AnalyticsEvents.record("\(prefix)after-2")
            sessionControl.send(.open(duration: 60))
            while let snapshot = await arrivals.next() {
                if snapshot.sessionID != nil && snapshot.sessionID != firstSession { break }
            }
            AnalyticsEvents.record("\(prefix)second-session")
            var second: [AnalyticsEventsMirror.Snapshot] = []
            while let snapshot = await arrivals.next() {
                second.append(snapshot)
                if !ours(snapshot).isEmpty { break }
            }

            let seenInFirst = (opened + during).filter { $0.sessionID == firstSession }.flatMap(ours)
            #expect(Set(seenInFirst).isSubset(of: Set(expectedFirst)))
            #expect(during.last.map(ours) == expectedFirst)
            #expect(during.last?.events.filter { $0.name.hasPrefix(prefix) }.map(\.properties) == [["step": 1], ["step": 2], ["step": 3]])
            #expect(!servedAfterEnd)
            #expect(second.last.map(ours) == expectedSecond)
            #expect(second.flatMap(ours).allSatisfy { $0 == expectedSecond[0] })
        }

        @Test("Events recorded after a session expires don't reach the sidecar, nor do those from before it")
        func onlyDuringSessionAfterExpiry() async throws {
            let prefix = "expiry-\(UUID().uuidString)-"
            let directory = FileManager.default.temporaryDirectory.appending(path: "AnalyticsMirrorSessionTests-\(UUID().uuidString)")
            let clock = MovableClock(Date(timeIntervalSinceReferenceDate: 800_000_000))
            let timer = ManualTimer()
            let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: clock, timer: timer)
            let receiver = DebugDrawerReceiver(directory: directory, sessions: sessions)
            let mirror = AnalyticsEventsMirror(sessions: sessions, redaction: .standard, capacity: 100) { clock.now }
            receiver.enable(.model(mirror, id: AnalyticsEventsMirror.pluginID, scope: .persistent))
            try receiver.start()
            defer { receiver.stop() }
            let sidecar = try DebugDrawerAppGroupStoreTransport(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
            let sessionControl = try await sidecar.connect(
                toPlugin: DebugDrawerSessions.pluginID, snapshot: DebugDrawerSessionState.self, command: DebugDrawerSessionCommand.self
            )
            func ours(_ snapshot: AnalyticsEventsMirror.Snapshot) -> [String] {
                snapshot.events.map(\.name).filter { $0.hasPrefix(prefix) }
            }
            let expectedFirst = ["\(prefix)during-1", "\(prefix)during-2"]
            let expectedSecond = ["\(prefix)second-session"]

            AnalyticsEvents.record("\(prefix)before")
            sessionControl.send(.open(duration: 60))
            // Served once the session is open.
            let events = try await sidecar.connect(
                toPlugin: AnalyticsEventsMirror.pluginID, snapshot: AnalyticsEventsMirror.Snapshot.self, command: AnalyticsEventsMirror.Command.self
            )
            var arrivals = events.snapshots().makeAsyncIterator()
            var opened: [AnalyticsEventsMirror.Snapshot] = []
            while let snapshot = await arrivals.next() {
                opened.append(snapshot)
                if snapshot.sessionID != nil { break }
            }
            AnalyticsEvents.record("\(prefix)during-1")
            AnalyticsEvents.record("\(prefix)during-2")
            var during: [AnalyticsEventsMirror.Snapshot] = []
            while let snapshot = await arrivals.next() {
                during.append(snapshot)
                if ours(snapshot).count >= 2 { break }
            }
            let firstSession = try #require(opened.last?.sessionID)
            clock.advance(by: 61)
            // Past the expiry, before its timer fires, as in an app back from suspension.
            AnalyticsEvents.record("\(prefix)past-expiry")
            timer.fire()
            for await state in sessionControl.snapshots() where !state.isActive {
                break
            }
            let snapshotFile = AppGroupStoreLayout(directory: receiver.appDirectory).snapshotFile(for: AnalyticsEventsMirror.pluginID)
            let servedAfterExpiry = FileManager.default.fileExists(atPath: snapshotFile.path)
            AnalyticsEvents.record("\(prefix)after-expiry")
            sessionControl.send(.open(duration: 60))
            while let snapshot = await arrivals.next() {
                if snapshot.sessionID != nil && snapshot.sessionID != firstSession { break }
            }
            AnalyticsEvents.record("\(prefix)second-session")
            var second: [AnalyticsEventsMirror.Snapshot] = []
            while let snapshot = await arrivals.next() {
                second.append(snapshot)
                if !ours(snapshot).isEmpty { break }
            }

            #expect(during.last.map(ours) == expectedFirst)
            #expect((opened + during).flatMap(ours).allSatisfy(expectedFirst.contains))
            #expect(!servedAfterExpiry)
            #expect(second.last.map(ours) == expectedSecond)
            #expect(sessions.auditLog.contains { $0.event == .sessionEnded(.expired) })
        }
    }
#endif
