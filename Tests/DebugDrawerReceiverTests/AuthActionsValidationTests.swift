// What the auth actions refuse as they are made. Real in every build, so these run in debug and
// release alike.
import DebugDrawerReceiver
import Foundation
import Testing

@MainActor
@Suite
struct AuthActionsValidationTests {
    @Test("Two auth actions with one ID throw DuplicateID")
    func repeatedActionID() {
        #expect(throws: DebugDrawerAuthActions.DuplicateID.self) {
            _ = try DebugDrawerAuthActions(actions: [
                .logOut { .succeeded },
                DebugDrawerAuthAction("log-out", title: "Log Out Again") { .succeeded }
            ])
        }
    }

    @Test("The capability made over actions with one ID throws DuplicateID too")
    func repeatedActionIDThroughTheCapability() {
        #expect(throws: DebugDrawerAuthActions.DuplicateID.self) {
            _ = try DebugDrawerReceiverCapability.authActions([
                .forceRefresh { .succeeded },
                .forceRefresh { .failed("Not signed in") }
            ])
        }
    }

    @Test("The three well-known actions have IDs of their own and are taken together")
    func wellKnownActions() throws {
        let expected = ["expire-access-token", "force-refresh", "log-out"]

        let sut = try DebugDrawerAuthActions(actions: [
            .expireAccessToken { .succeeded },
            .forceRefresh { .succeeded },
            .logOut { .succeeded }
        ])

        #expect(sut.snapshot.actions.map(\.id) == expected)
    }

    @Test("No actions are taken and list nothing")
    func noActions() throws {
        let sut = try DebugDrawerAuthActions(actions: [])

        #expect(sut.snapshot.actions.isEmpty)
    }
}
