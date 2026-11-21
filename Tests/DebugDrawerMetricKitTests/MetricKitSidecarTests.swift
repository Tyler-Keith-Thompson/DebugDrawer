// The MetricKit capability as a sidecar reaches it: a real DebugDrawerReceiver serving the
// app-group store, and the sidecar's DebugDrawerAppGroupStoreTransport (a debug-build type)
// reading it from the same directory, opening sessions through the sessions' own model. MetricKit
// can't be made to deliver a payload, so a hand-written source hands the mirror the fixtures
// through the subscriber's entry point, as MXMetricManager hands over its past payloads.
#if DEBUG
    import Combine
    import DebugDrawer
    @testable import DebugDrawerMetricKit
    @testable import DebugDrawerReceiver
    import DebugDrawerTestSupport
    import Foundation
    import Testing

    /// Hands over `held` as it is subscribed, as MetricKit does with its past payloads.
    @MainActor
    private final class HeldPayloadsSource: MetricKitPayloadSource {
        let held: [ReceivedMetricKitPayload]

        init(held: [ReceivedMetricKitPayload]) {
            self.held = held
        }

        func subscribe(_ receive: @escaping @MainActor ([ReceivedMetricKitPayload]) -> Void) {
            receive(held)
        }

        func unsubscribe() {}
    }

    @MainActor
    @Suite(.serialized, .timeLimit(.minutes(1)))
    struct MetricKitSidecarTests {
        @Test("MetricKit's metric and diagnostic payloads are forwarded to the sidecar's session, redacted, and none before it opens")
        func payloadsForwarded() async throws {
            let root = FileManager.default.temporaryDirectory.appending(path: "MetricKitSidecarTests-\(UUID().uuidString)")
            let store = root.appending(path: "Group/DebugDrawer")
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let receiver = DebugDrawerReceiver(directory: store, sessions: sessions)
            let source = HeldPayloadsSource(held: [
                ReceivedMetricKitPayload(kind: .metrics, json: MetricKitFixtures.metricPayload),
                ReceivedMetricKitPayload(kind: .diagnostics, json: MetricKitFixtures.crashDiagnosticPayload)
            ])
            let mirror = MetricKitPayloadsMirror(
                sessions: sessions, directory: root.appending(path: "Payloads"), redaction: .standard, capacity: 10, source: source
            )
            receiver.enable(.model(mirror, id: MetricKitPayloadsMirror.pluginID, scope: .persistent))
            try receiver.start()
            defer { receiver.stop() }
            let sidecar = try DebugDrawerAppGroupStoreTransport(directory: AppGroupStoreLayout.appDirectory(inStore: store))
            let sessionControl = try await sidecar.connect(
                toPlugin: DebugDrawerSessions.pluginID, snapshot: DebugDrawerSessionState.self, command: DebugDrawerSessionCommand.self
            )
            let snapshotFile = AppGroupStoreLayout(directory: receiver.appDirectory).snapshotFile(for: MetricKitPayloadsMirror.pluginID)

            let servedBeforeSession = FileManager.default.fileExists(atPath: snapshotFile.path)
            sessionControl.send(.open(duration: 60))
            // Served once the session is open.
            let payloads = try await sidecar.connect(
                toPlugin: MetricKitPayloadsMirror.pluginID,
                snapshot: MetricKitPayloadsMirror.Snapshot.self,
                command: MetricKitPayloadsMirror.Command.self
            )
            var arrivals = payloads.snapshots().makeAsyncIterator()
            var during: MetricKitPayloadsMirror.Snapshot?
            while let snapshot = await arrivals.next() {
                if snapshot.sessionID != nil {
                    during = snapshot
                    break
                }
            }

            #expect(!servedBeforeSession)
            let served = try #require(during?.payloads)
            #expect(served.map(\.kind) == [.diagnostics, .metrics])
            let metrics = try #require(served.last)
            let metricObject = try #require(try JSONSerialization.jsonObject(with: metrics.json) as? [String: Any])
            #expect(metricObject["appVersion"] as? String == "1.2")
            #expect((metricObject["signpostMetrics"] as? [[String: Any]])?.first?["signpostName"] as? String == "LoadFeed")
            let crash = try #require(served.first)
            let crashObject = try #require(try JSONSerialization.jsonObject(with: crash.json) as? [String: Any])
            let diagnostic = try #require((crashObject["crashDiagnostics"] as? [[String: Any]])?.first)
            let metadata = try #require(diagnostic["diagnosticMetaData"] as? [String: Any])
            #expect(metadata["signal"] as? Int == 11)
            #expect((metadata["objectiveCexceptionReason"] as? [String: Any])?["composedMessage"] as? String == MetricKitRedaction.mask)
            #expect(crash.json.range(of: Data(MetricKitFixtures.crashCustomerEmail.utf8)) == nil)
        }

        @Test("With no MetricKit payload present, the sidecar's session is served none")
        func nonePresent() async throws {
            let root = FileManager.default.temporaryDirectory.appending(path: "MetricKitSidecarTests-\(UUID().uuidString)")
            let store = root.appending(path: "Group/DebugDrawer")
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let receiver = DebugDrawerReceiver(directory: store, sessions: sessions)
            let mirror = MetricKitPayloadsMirror(
                sessions: sessions, directory: root.appending(path: "Payloads"), redaction: .standard, capacity: 10,
                source: HeldPayloadsSource(held: [])
            )
            receiver.enable(.model(mirror, id: MetricKitPayloadsMirror.pluginID, scope: .persistent))
            try receiver.start()
            defer { receiver.stop() }
            let sidecar = try DebugDrawerAppGroupStoreTransport(directory: AppGroupStoreLayout.appDirectory(inStore: store))
            let sessionControl = try await sidecar.connect(
                toPlugin: DebugDrawerSessions.pluginID, snapshot: DebugDrawerSessionState.self, command: DebugDrawerSessionCommand.self
            )

            sessionControl.send(.open(duration: 60))
            // Served once the session is open.
            let payloads = try await sidecar.connect(
                toPlugin: MetricKitPayloadsMirror.pluginID,
                snapshot: MetricKitPayloadsMirror.Snapshot.self,
                command: MetricKitPayloadsMirror.Command.self
            )
            var arrivals = payloads.snapshots().makeAsyncIterator()
            var during: MetricKitPayloadsMirror.Snapshot?
            while let snapshot = await arrivals.next() {
                if snapshot.sessionID != nil {
                    during = snapshot
                    break
                }
            }

            #expect(during?.sessionID != nil)
            #expect(during?.payloads.isEmpty == true)
        }

        @Test("Deleting from the sidecar outside a session is refused; inside one it deletes")
        func deleteOnlyInSession() async throws {
            let root = FileManager.default.temporaryDirectory.appending(path: "MetricKitSidecarTests-\(UUID().uuidString)")
            let store = root.appending(path: "Group/DebugDrawer")
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let receiver = DebugDrawerReceiver(directory: store, sessions: sessions)
            let mirror = MetricKitPayloadsMirror(
                sessions: sessions, directory: root.appending(path: "Payloads"), redaction: .standard, capacity: 10,
                source: HeldPayloadsSource(held: [ReceivedMetricKitPayload(kind: .metrics, json: MetricKitFixtures.metricPayload)])
            )
            receiver.enable(.model(mirror, id: MetricKitPayloadsMirror.pluginID, scope: .persistent))
            try receiver.start()
            defer { receiver.stop() }
            let sidecar = try DebugDrawerAppGroupStoreTransport(directory: AppGroupStoreLayout.appDirectory(inStore: store))
            let sessionControl = try await sidecar.connect(
                toPlugin: DebugDrawerSessions.pluginID, snapshot: DebugDrawerSessionState.self, command: DebugDrawerSessionCommand.self
            )
            let (auditEntries, auditEntry) = AsyncStream<DebugDrawerAuditEntry>.makeStream()
            let subscription = sessions.auditEntries.sink { auditEntry.yield($0) }
            defer { subscription.cancel() }
            var audit = auditEntries.makeAsyncIterator()
            // Outside a session the capability isn't served, so a sidecar can't connect to it: the
            // command is left in the store as its transport would leave it.
            let layout = AppGroupStoreLayout(directory: receiver.appDirectory)
            let deleteAll = try StoreDocument(TransportMessage(
                kind: .command, pluginID: MetricKitPayloadsMirror.pluginID,
                payload: TransportMessage.payload(MetricKitPayloadsMirror.Command.deleteAll)
            )).encoded()

            try layout.write(deleteAll, to: layout.commands.appending(path: "delete-all.json"))
            let refusal = await audit.next()
            sessionControl.send(.open(duration: 60))
            // Served once the session is open.
            let payloads = try await sidecar.connect(
                toPlugin: MetricKitPayloadsMirror.pluginID,
                snapshot: MetricKitPayloadsMirror.Snapshot.self,
                command: MetricKitPayloadsMirror.Command.self
            )
            var arrivals = payloads.snapshots().makeAsyncIterator()
            var opened: MetricKitPayloadsMirror.Snapshot?
            while let snapshot = await arrivals.next() {
                if snapshot.sessionID != nil {
                    opened = snapshot
                    break
                }
            }
            payloads.send(.deleteAll)
            var afterDelete: MetricKitPayloadsMirror.Snapshot?
            while let snapshot = await arrivals.next() {
                if snapshot.payloads.isEmpty {
                    afterDelete = snapshot
                    break
                }
            }

            #expect(refusal?.capability == MetricKitPayloadsMirror.pluginID)
            #expect(refusal?.event == .commandRefused(.noActiveSession))
            #expect(opened?.payloads.count == 1)
            #expect(afterDelete?.sessionID == opened?.sessionID)
        }
    }
#endif
