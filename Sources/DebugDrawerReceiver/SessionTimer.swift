import Foundation

/// Calls back once, at a session's expiry. Tests pass a fake that records the date it was
/// given and fires when the test says. `package`, so the sidecar kit's relay stops at a session's
/// expiry on the same timer.
@MainActor
package protocol SessionTimer: AnyObject {
    /// Calls `fire` once at `date`, or as soon as it can when `date` has passed, in place of
    /// any call scheduled before.
    func schedule(at date: Date, _ fire: @escaping @MainActor () -> Void)

    /// Cancels the scheduled call; does nothing when none is.
    func cancel()
}
