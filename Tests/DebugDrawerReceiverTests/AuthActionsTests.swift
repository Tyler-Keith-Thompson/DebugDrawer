@testable import DebugDrawerReceiver
import Foundation
import Testing

// The auth actions' model on its own: the well-known actions, a run from request to outcome, a
// failure's message, which run an outcome lands on, and the snapshot's schema, which has no field
// for a credential.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct AuthActionsTests {
    private static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test("The well-known actions have fixed IDs and titles, and summaries the host may replace")
    func wellKnownActions() {
        let expected = [
            ["expire-access-token", "Expire Access Token", "The next request meets an expired token"],
            ["force-refresh", "Force Token Refresh", "Refreshes the tokens now"],
            ["log-out", "Log Out", "Signs the app out, as its own Log Out does"],
            ["log-out", "Log Out", "Ends the trial account's sign-in"]
        ]

        let actual = [
            DebugDrawerAuthAction.expireAccessToken { .succeeded },
            .forceRefresh { .succeeded },
            .logOut { .succeeded },
            .logOut(summary: "Ends the trial account's sign-in") { .succeeded }
        ].map { [$0.id, $0.title, $0.summary] }

        #expect(actual == expected)
    }

    @Test("The snapshot lists every action in the host's order, none run yet, with the launch URL")
    func listsActions() throws {
        let launchURL = try #require(URL(string: "shop-internal://"))
        let expected = DebugDrawerAuthActions.Snapshot(
            actions: [
                DebugDrawerAuthActions.Entry(id: "log-out", title: "Log Out", summary: "Signs the app out, as its own Log Out does", lastRun: nil),
                DebugDrawerAuthActions.Entry(id: "revoke", title: "Revoke Refresh Token", summary: "", lastRun: nil)
            ],
            launchURL: launchURL
        )

        let sut = try DebugDrawerAuthActions(
            actions: [.logOut { .succeeded }, DebugDrawerAuthAction("revoke", title: "Revoke Refresh Token") { .succeeded }],
            launchURL: launchURL
        )

        #expect(sut.snapshot == expected)
    }

    @Test("A request runs the handler once, the run marked running until the handler returns, then succeeded")
    func runningThenSucceeded() async throws {
        let (gate, open) = AsyncStream<Void>.makeStream()
        var calls = 0
        let sut = try DebugDrawerAuthActions(actions: [
            .expireAccessToken {
                calls += 1
                var waiting = gate.makeAsyncIterator()
                _ = await waiting.next()
                return .succeeded
            }
        ], launchURL: nil, now: { Self.now })
        let expectedRunning = DebugDrawerAuthActions.Run(number: 1, started: Self.now, status: .running)
        let expectedDone = DebugDrawerAuthActions.Run(number: 1, started: Self.now, status: .succeeded)

        sut.perform(.perform(action: "expire-access-token"))
        let running = sut.snapshot.actions[0].lastRun
        open.yield()
        var done: DebugDrawerAuthActions.Run?
        for await snapshot in sut.$snapshot.values where snapshot.actions[0].lastRun?.status != .running {
            done = snapshot.actions[0].lastRun
            break
        }

        #expect(running == expectedRunning)
        #expect(done == expectedDone)
        #expect(calls == 1)
    }

    @Test("A failure's message reaches the snapshot, cut to the most a sidecar is shown")
    func failureMessage() async throws {
        let sut = try DebugDrawerAuthActions(actions: [
            .forceRefresh { .failed("Not signed in") },
            DebugDrawerAuthAction("long", title: "Long") {
                // A multi-line literal: a StaticString can't be concatenated or built at run time.
                .failed("""
                0123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789
                012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678
                overflow
                """)
            }
        ], launchURL: nil, now: { Self.now })
        let expectedShort = DebugDrawerAuthActions.Status.failed(message: "Not signed in")
        let expectedLength = DebugDrawerAuthActions.Run.maximumMessageLength

        sut.perform(.perform(action: "force-refresh"))
        sut.perform(.perform(action: "long"))
        var finished: DebugDrawerAuthActions.Snapshot?
        for await snapshot in sut.$snapshot.values where snapshot.actions.allSatisfy({ $0.lastRun?.status != .running }) {
            finished = snapshot
            break
        }

        #expect(finished?.actions[0].lastRun?.status == expectedShort)
        guard case let .failed(message) = finished?.actions[1].lastRun?.status else {
            Issue.record("The long failure didn't land")
            return
        }
        #expect(message.count == expectedLength)
        #expect(!message.contains("overflow"))
    }

    @Test("Runs are numbered across actions; an older run finishing after a newer one started leaves the newer one's status")
    func olderRunDoesNotOverwriteNewer() async throws {
        let (firstGate, openFirst) = AsyncStream<Void>.makeStream()
        var handlerCalls = 0
        let sut = try DebugDrawerAuthActions(actions: [
            .logOut { .succeeded },
            .forceRefresh {
                handlerCalls += 1
                if handlerCalls == 1 {
                    var waiting = firstGate.makeAsyncIterator()
                    _ = await waiting.next()
                    return .failed("The first refresh")
                }
                return .succeeded
            }
        ], launchURL: nil, now: { Self.now })

        sut.perform(.perform(action: "log-out"))
        sut.perform(.perform(action: "force-refresh"))
        sut.perform(.perform(action: "force-refresh"))
        for await snapshot in sut.$snapshot.values where snapshot.actions[1].lastRun?.status == .succeeded {
            break
        }
        openFirst.yield()
        // The first refresh's outcome changes nothing, so there is no snapshot to wait for. The
        // main actor runs its work in order: the first refresh, resumed by the gate, finishes
        // before a request made after it, so wait for that one's outcome.
        sut.perform(.perform(action: "log-out"))
        let expectedLater = DebugDrawerAuthActions.Run(number: 4, started: Self.now, status: .succeeded)
        for await snapshot in sut.$snapshot.values where snapshot.actions[0].lastRun == expectedLater {
            break
        }

        #expect(sut.snapshot.actions[1].lastRun?.number == 3)
        #expect(sut.snapshot.actions[1].lastRun?.status == .succeeded)
    }

    @Test("A request for an action the host didn't register is refused notExposed and, performed anyway, changes nothing")
    func unregisteredAction() throws {
        var calls = 0
        let sut = try DebugDrawerAuthActions(actions: [.logOut { calls += 1; return .succeeded }])
        let before = sut.snapshot

        let refusal = sut.refusal(of: .perform(action: "delete-account"))
        let allowed = sut.refusal(of: .perform(action: "log-out"))
        sut.perform(.perform(action: "delete-account"))

        #expect(refusal == .notExposed)
        #expect(allowed == nil)
        #expect(sut.snapshot == before)
        #expect(calls == 0)
    }

    @Test("The snapshot's schema, every field filled, has no field for a token, credential or secret")
    func schemaHasNoCredentialField() throws {
        let run = DebugDrawerAuthActions.Run(number: 1, started: Self.now, status: .failed(message: "Not signed in"))
        let snapshot = DebugDrawerAuthActions.Snapshot(
            actions: [DebugDrawerAuthActions.Entry(id: "log-out", title: "Log Out", summary: "Signs out", lastRun: run)],
            launchURL: URL(string: "shop-internal://")
        )
        let expected: Set<String> = [
            "actions", "launchURL", "id", "title", "summary", "lastRun", "number", "started", "status", "failed", "message"
        ]
        let statuses: [DebugDrawerAuthActions.Status] = [.running, .succeeded]

        /// Every key of every object in `value`, at any depth.
        func keys(of value: Any) -> Set<String> {
            switch value {
            case let object as [String: Any]: Set(object.keys).union(object.values.flatMap(keys(of:)))
            case let array as [Any]: Set(array.flatMap(keys(of:)))
            default: []
            }
        }
        let actual = try keys(of: JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)))
        let otherStatuses = try statuses.map { try keys(of: JSONSerialization.jsonObject(with: JSONEncoder().encode($0))) }

        #expect(actual == expected)
        #expect(otherStatuses == [["running"], ["succeeded"]])
        #expect(!actual.contains { ["token", "credential", "secret", "password", "cookie"].contains(where: $0.lowercased().contains) })
    }
}
