// The clock and timer are copied from DebugDrawerNotificationsTests, as each test target keeps its
// own fakes: the test drives them, so a session expires when it says. The verifier stands in for a
// company's grant server, so a test can open a session under a grant listing what it chooses.
#if DEBUG
    import CoreLocation
    import DebugDrawerLocation
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

    /// Accepts every token as a grant for `audience` valid for an hour either side of `date`, under
    /// the token as its ID (so each opens one session), listing the capabilities named in the
    /// token, comma-separated.
    struct ListingGrantVerifier: DebugDrawerGrantVerifier {
        let audience: String
        let date: Date

        func verify(_ token: String) throws(DebugDrawerGrantVerificationError) -> DebugDrawerGrant {
            DebugDrawerGrant(
                id: token, subject: "employee@example.com", audiences: [audience],
                capabilities: token.split(separator: ",").map(String.init),
                notBefore: date.addingTimeInterval(-3600), expires: date.addingTimeInterval(3600)
            )
        }
    }

    /// A host's location consumer: the coordinate of every location `spoofingDidChange` handed it,
    /// in order, `nil` for each end.
    @MainActor
    final class SpoofingObserver {
        private(set) var told: [LocationCoordinate?] = []

        func spoofingDidChange(_ location: CLLocation?) {
            told.append(location.map { LocationCoordinate($0.coordinate) })
        }
    }
#endif
