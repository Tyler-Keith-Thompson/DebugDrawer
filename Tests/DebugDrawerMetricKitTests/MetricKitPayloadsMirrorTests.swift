// The mirror's own rules, with a hand-written source standing in for MXMetricManager, which
// delivers on its own schedule and nothing in a test runner: what is kept, across launches (a
// second mirror over the same directory), and what the snapshot shows with and without a session.
#if DEBUG
    @testable import DebugDrawerMetricKit
    @testable import DebugDrawerReceiver
    import DebugDrawerTestSupport
    import Foundation
    import Testing

    /// Hands over `held` as it is subscribed, as MetricKit does with its past payloads, and
    /// whatever the test delivers later.
    @MainActor
    private final class FakeSource: MetricKitPayloadSource {
        var held: [ReceivedMetricKitPayload]
        private(set) var receive: (@MainActor ([ReceivedMetricKitPayload]) -> Void)?
        private(set) var unsubscriptions = 0

        init(held: [ReceivedMetricKitPayload] = []) {
            self.held = held
        }

        func subscribe(_ receive: @escaping @MainActor ([ReceivedMetricKitPayload]) -> Void) {
            self.receive = receive
            receive(held)
        }

        func unsubscribe() {
            receive = nil
            unsubscriptions += 1
        }

        func deliver(_ payloads: [ReceivedMetricKitPayload]) {
            receive?(payloads)
        }
    }

    /// Accepts every token as a grant for `audience` listing `capabilities`, valid at any time,
    /// under an ID of the token itself, so each token opens one session: it stands in for a
    /// company's grant server.
    private struct AcceptingGrantVerifier: DebugDrawerGrantVerifier {
        let audience: String
        let capabilities: [String]

        func verify(_ token: String) throws(DebugDrawerGrantVerificationError) -> DebugDrawerGrant {
            DebugDrawerGrant(
                id: token, subject: "employee@example.com", audiences: [audience], capabilities: capabilities,
                notBefore: .distantPast, expires: .distantFuture
            )
        }
    }

    @MainActor
    @Suite
    struct MetricKitPayloadsMirrorTests {
        @Test("Nothing is served while no session is open; the payloads kept are served as one opens, and none once it ends")
        func servedOnlyDuringSession() {
            let directory = FileManager.default.temporaryDirectory.appending(path: "MetricKitPayloadsMirrorTests-\(UUID().uuidString)")
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let source = FakeSource(held: [ReceivedMetricKitPayload(kind: .diagnostics, json: MetricKitFixtures.crashDiagnosticPayload)])
            let sut = MetricKitPayloadsMirror(sessions: sessions, directory: directory, redaction: .standard, capacity: 10, source: source)

            let beforeSession = sut.snapshot
            sessions.perform(.open(duration: 60))
            let expectedSessionID = sessions.snapshot.session?.id
            let during = sut.snapshot
            sessions.end()
            let afterSession = sut.snapshot

            #expect(beforeSession == MetricKitPayloadsMirror.Snapshot(sessionID: nil, payloads: []))
            #expect(expectedSessionID != nil)
            #expect(during.sessionID == expectedSessionID)
            #expect(during.payloads.map(\.kind) == [.diagnostics])
            #expect(afterSession == MetricKitPayloadsMirror.Snapshot(sessionID: nil, payloads: []))
        }

        @Test("A payload arriving during a session is served at once")
        func arrivesDuringSession() throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: "MetricKitPayloadsMirrorTests-\(UUID().uuidString)")
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let source = FakeSource()
            let sut = MetricKitPayloadsMirror(sessions: sessions, directory: directory, redaction: .standard, capacity: 10, source: source)
            sessions.perform(.open(duration: 60))
            // The fixture's timeStampBegin, 2026-11-17 00:00:00 +0000.
            let expected = Date(timeIntervalSince1970: 1_794_873_600)

            source.deliver([ReceivedMetricKitPayload(kind: .metrics, json: MetricKitFixtures.metricPayload)])

            let actual = try #require(sut.snapshot.payloads.first)
            #expect(sut.snapshot.payloads.count == 1)
            #expect(actual.kind == .metrics)
            #expect(actual.begin == expected)
        }

        @Test("With no payload present, a session is served none")
        func nonePresent() {
            let directory = FileManager.default.temporaryDirectory.appending(path: "MetricKitPayloadsMirrorTests-\(UUID().uuidString)")
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let sut = MetricKitPayloadsMirror(sessions: sessions, directory: directory, redaction: .standard, capacity: 10, source: FakeSource())

            sessions.perform(.open(duration: 60))

            #expect(sut.snapshot.sessionID != nil)
            #expect(sut.snapshot.payloads.isEmpty)
        }

        @Test("Payloads are kept across launches, redacted on disk, each once however often MetricKit delivers it")
        func keptAcrossLaunches() throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: "MetricKitPayloadsMirrorTests-\(UUID().uuidString)")
            let crash = ReceivedMetricKitPayload(kind: .diagnostics, json: MetricKitFixtures.crashDiagnosticPayload)
            let metrics = ReceivedMetricKitPayload(kind: .metrics, json: MetricKitFixtures.metricPayload)
            let firstLaunch = DebugDrawerSessions(maximumDuration: 300)
            let firstSource = FakeSource(held: [crash])
            let first = MetricKitPayloadsMirror(sessions: firstLaunch, directory: directory, redaction: .standard, capacity: 10, source: firstSource)
            firstSource.deliver([crash, metrics])
            _ = first
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let sut = MetricKitPayloadsMirror(
                sessions: sessions, directory: directory, redaction: .standard, capacity: 10, source: FakeSource(held: [crash])
            )

            sessions.perform(.open(duration: 60))

            let actual = sut.snapshot.payloads
            #expect(actual.map(\.kind) == [.diagnostics, .metrics])
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            #expect(files.count == 2)
            for file in files {
                // The file encodes the payload's JSON as base64, so it is decoded before searching.
                let kept = try JSONDecoder().decode(MetricKitPayloadsMirror.Payload.self, from: Data(contentsOf: file))
                #expect(kept.json.range(of: Data(MetricKitFixtures.crashCustomerEmail.utf8)) == nil)
            }
        }

        @Test("The newest payloads are kept up to the capacity: the one whose period ended first goes")
        func capacity() {
            let directory = FileManager.default.temporaryDirectory.appending(path: "MetricKitPayloadsMirrorTests-\(UUID().uuidString)")
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let source = FakeSource()
            let sut = MetricKitPayloadsMirror(sessions: sessions, directory: directory, redaction: .standard, capacity: 2, source: source)
            sessions.perform(.open(duration: 60))
            let payloads = (1 ... 3).map { day in
                ReceivedMetricKitPayload(
                    kind: .metrics,
                    json: Data(#"{"day":\#(day)}"#.utf8),
                    begin: Date(timeIntervalSince1970: Double(day) * 86400),
                    end: Date(timeIntervalSince1970: Double(day + 1) * 86400)
                )
            }
            let expected = [Data(#"{"day":3}"#.utf8), Data(#"{"day":2}"#.utf8)]

            source.deliver(payloads)

            #expect(sut.snapshot.payloads.map(\.json) == expected)
            #expect((try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)).count) == 2)
        }

        @Test("JSON that isn't an object, or larger than the limit once redacted, is dropped")
        func dropsUnreadableAndOversized() {
            let directory = FileManager.default.temporaryDirectory.appending(path: "MetricKitPayloadsMirrorTests-\(UUID().uuidString)")
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let source = FakeSource()
            let sut = MetricKitPayloadsMirror(
                sessions: sessions, directory: directory, redaction: .standard, capacity: 10, maximumPayloadSize: 64, source: source
            )
            sessions.perform(.open(duration: 60))
            let fits = Data(#"{"a":1}"#.utf8)
            let tooLarge = Data(#"{"a":"\#(String(repeating: "x", count: 64))"}"#.utf8)

            source.deliver([
                ReceivedMetricKitPayload(kind: .metrics, json: Data("[1, 2]".utf8)),
                ReceivedMetricKitPayload(kind: .metrics, json: Data("not json".utf8)),
                ReceivedMetricKitPayload(kind: .metrics, json: tooLarge),
                ReceivedMetricKitPayload(kind: .metrics, json: fits)
            ])

            #expect(sut.snapshot.payloads.map(\.json) == [fits])
        }

        @Test("A deleted payload is gone from the app, and MetricKit delivering it again, then or at a later launch, doesn't bring it back")
        func deleteStaysDeleted() throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: "MetricKitPayloadsMirrorTests-\(UUID().uuidString)")
            let crash = ReceivedMetricKitPayload(kind: .diagnostics, json: MetricKitFixtures.crashDiagnosticPayload)
            let metrics = ReceivedMetricKitPayload(kind: .metrics, json: MetricKitFixtures.metricPayload)
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let source = FakeSource(held: [crash, metrics])
            let sut = MetricKitPayloadsMirror(sessions: sessions, directory: directory, redaction: .standard, capacity: 10, source: source)
            sessions.perform(.open(duration: 60))
            let crashID = try #require(sut.snapshot.payloads.first { $0.kind == .diagnostics }?.id)

            sut.perform(.delete(id: crashID))
            let afterDelete = sut.snapshot.payloads.map(\.kind)
            source.deliver([crash])
            let afterRedelivery = sut.snapshot.payloads.map(\.kind)
            let relaunchSessions = DebugDrawerSessions(maximumDuration: 300)
            let relaunched = MetricKitPayloadsMirror(
                sessions: relaunchSessions, directory: directory, redaction: .standard, capacity: 10, source: FakeSource(held: [crash, metrics])
            )
            relaunchSessions.perform(.open(duration: 60))
            let afterRelaunch = relaunched.snapshot.payloads.map(\.kind)
            relaunched.perform(.deleteAll)

            #expect(afterDelete == [.metrics])
            #expect(afterRedelivery == [.metrics])
            #expect(afterRelaunch == [.metrics])
            #expect(relaunched.snapshot.payloads.isEmpty)
            #expect(relaunched.snapshot.sessionID != nil)
        }

        @Test("Releasing the mirror unsubscribes it from its source")
        func unsubscribesOnRelease() {
            let directory = FileManager.default.temporaryDirectory.appending(path: "MetricKitPayloadsMirrorTests-\(UUID().uuidString)")
            let source = FakeSource()
            var sut: MetricKitPayloadsMirror? = MetricKitPayloadsMirror(
                sessions: DebugDrawerSessions(maximumDuration: 300), directory: directory, redaction: .standard, capacity: 10, source: source
            )
            _ = sut

            sut = nil

            #expect(source.unsubscriptions == 1)
        }

        @Test("Under a grant policy, a session whose grant doesn't list the capability is served no payloads, kept or arriving")
        func grantWithoutCapability() {
            let directory = FileManager.default.temporaryDirectory.appending(path: "MetricKitPayloadsMirrorTests-\(UUID().uuidString)")
            let policy = DebugDrawerGrantPolicy(
                verifier: AcceptingGrantVerifier(audience: "com.example.app", capabilities: ["DebugDrawer.FeatureFlagOverrides"]),
                audience: "com.example.app"
            )
            let sessions = DebugDrawerSessions(maximumDuration: 300, grantPolicy: policy)
            let source = FakeSource(held: [ReceivedMetricKitPayload(kind: .diagnostics, json: MetricKitFixtures.crashDiagnosticPayload)])
            let sut = MetricKitPayloadsMirror(sessions: sessions, directory: directory, redaction: .standard, capacity: 10, source: source)

            sessions.perform(.open(duration: 60, grant: "flags-only"))
            let opened = sut.snapshot
            source.deliver([ReceivedMetricKitPayload(kind: .metrics, json: MetricKitFixtures.metricPayload)])

            #expect(sessions.snapshot.isActive)
            let expected = MetricKitPayloadsMirror.Snapshot(sessionID: sessions.snapshot.session?.id, payloads: [])
            #expect(opened == expected)
            #expect(sut.snapshot == expected)
        }

        @Test("Under a grant policy, a session whose grant lists the capability is served the payloads kept and those arriving")
        func grantWithCapability() {
            let directory = FileManager.default.temporaryDirectory.appending(path: "MetricKitPayloadsMirrorTests-\(UUID().uuidString)")
            let policy = DebugDrawerGrantPolicy(
                verifier: AcceptingGrantVerifier(audience: "com.example.app", capabilities: [MetricKitPayloadsMirror.pluginID]),
                audience: "com.example.app"
            )
            let sessions = DebugDrawerSessions(maximumDuration: 300, grantPolicy: policy)
            let source = FakeSource(held: [ReceivedMetricKitPayload(kind: .diagnostics, json: MetricKitFixtures.crashDiagnosticPayload)])
            let sut = MetricKitPayloadsMirror(sessions: sessions, directory: directory, redaction: .standard, capacity: 10, source: source)

            sessions.perform(.open(duration: 60, grant: "metrickit"))
            let opened = sut.snapshot.payloads.map(\.kind)
            source.deliver([ReceivedMetricKitPayload(kind: .metrics, json: MetricKitFixtures.metricPayload)])

            #expect(sut.snapshot.sessionID == sessions.snapshot.session?.id)
            #expect(opened == [.diagnostics])
            #expect(Set(sut.snapshot.payloads.map(\.kind)) == [.diagnostics, .metrics])
        }
    }
#endif
