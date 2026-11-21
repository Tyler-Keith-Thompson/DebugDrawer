import DebugDrawerReceiver
import Foundation

// The capability lives with the categories and their deletion, not in the receiver: the receiver
// knows models, not plugins, and a host that doesn't offer a reset links none of it (WebKit's
// cookie store among it). Deleted state can't be restored, so its scope is persistent; the
// sessions still gate every command.

public extension DebugDrawerReceiverCapability {
    /// App state reset: within a session, a sidecar lists what each category the host allows
    /// would clear (UserDefaults, files, caches, cookies, the URL cache, the app's own cleanup,
    /// and the keychain only where the host allows it on its own) and, once the employee confirms
    /// that list, the app clears exactly it as it next comes to the foreground, as a fresh install
    /// would leave it, and reports what it cleared.
    ///
    /// The risk it takes is data loss on the employee's own device: what a reset deletes doesn't
    /// come back. It is off until the host enables it, and limited to the categories the host
    /// passes ``AppStateResetRequests/init(sessions:allowing:allowingKeychain:appGroups:directories:cleanup:launchURL:)``;
    /// `.all` leaves the keychain out, which a host allows with `allowingKeychain: true` alone.
    /// Nothing is read until the sidecar asks, in a session: the listing names keys, paths, sizes,
    /// cookie domains and keychain services, never a value or an account. A reset confirms each
    /// category's listing at its revision: one of a category the host didn't allow is refused
    /// (``/DebugDrawerReceiver/DebugDrawerAuditEntry/Refusal/notExposed``), one whose listing
    /// changed since (``/DebugDrawerReceiver/DebugDrawerAuditEntry/Refusal/staleConfirmation``),
    /// and one whose categories hold something else by the time it runs deletes nothing
    /// (``AppStateResetRequests/Outcome/notApplied(changed:)``).
    /// DebugDrawer's own state stays: its defaults keys, its files and the receiver's store,
    /// sessions and audit log. Each request is written to the audit log as
    /// ``/DebugDrawerReceiver/DebugDrawerAuditEntry/Event/commandApplied``. Add
    /// ``/DebugDrawerReceiver/DebugDrawerReceiverCapability/requiringGrant()`` to need a signed
    /// grant for it.
    ///
    /// The app keeps running after a reset, so what it holds in memory stays until it next
    /// launches; supply an ``AppStateReset/Cleanup`` to clear that too.
    ///
    /// ```swift
    /// let appStateReset = AppStateResetRequests(sessions: sessions, allowing: [.caches, .urlCache])
    /// receiver.enable(.appStateReset(appStateReset))
    /// ```
    ///
    /// - Parameter requests: The resets, made with the receiver's sessions.
    /// - Returns: The capability, under ``AppStateResetRequests/pluginID``.
    static func appStateReset(_ requests: AppStateResetRequests) -> Self {
        var capability = Self.model(requests, id: AppStateResetRequests.pluginID, scope: .persistent, refusal: requests.refusal(of:))
        capability.enabled = { snapshotFile, _ in requests.keepStore(ofSnapshotFile: snapshotFile) }
        return capability
    }
}
