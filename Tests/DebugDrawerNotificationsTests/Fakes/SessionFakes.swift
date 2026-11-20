// The clock and timer are copied from DebugDrawerNetworkTests, as each test target keeps its own
// fakes: the test drives them, so a session expires when it says. The verifier stands in for a
// company's grant server, so a test can open a session under a grant listing what it chooses.
#if DEBUG
    @testable import DebugDrawerReceiver
    import Foundation
    import os

    /// A wall clock the test moves by hand.
    final class MovableClock: SessionClock, Sendable {
        private let time: OSAllocatedUnfairLock<Date>

        init(_ start: Date) {
            time = OSAllocatedUnfairLock(initialState: start)
        }

        var now: Date {
            time.withLock { $0 }
        }

        func set(_ date: Date) {
            time.withLock { $0 = date }
        }
    }

    /// A session timer that fires when the test says.
    @MainActor
    final class ManualTimer: SessionTimer {
        private(set) var scheduled: Date?
        private var fire: (@MainActor () -> Void)?

        func schedule(at date: Date, _ fire: @escaping @MainActor () -> Void) {
            scheduled = date
            self.fire = fire
        }

        func cancel() {
            scheduled = nil
            fire = nil
        }

        /// Fires the scheduled call, as the system's timer would at the expiry date.
        func fireNow() {
            let fire = fire
            cancel()
            fire?()
        }
    }

    /// Accepts every token as a grant for `audience` listing `capabilities`, valid for an hour
    /// either side of now, under an ID of the token itself, so each token opens one session.
    struct AcceptingGrantVerifier: DebugDrawerGrantVerifier {
        let audience: String
        let capabilities: [String]

        func verify(_ token: String) throws(DebugDrawerGrantVerificationError) -> DebugDrawerGrant {
            DebugDrawerGrant(
                id: token, subject: "employee@example.com", audiences: [audience], capabilities: capabilities,
                notBefore: Date().addingTimeInterval(-3600), expires: Date().addingTimeInterval(3600)
            )
        }
    }
#endif
