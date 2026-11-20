import Foundation

/// The app's state cleared as deleting the app and installing it again would leave it:
/// UserDefaults, keychain items, the files in the app's containers, caches, cookies, the URL
/// cache, and any cleanup of the app's own, by ``Category``.
///
/// Two things clear it. In a debug build, the Reset App State plugin
/// (`DebugDrawerAppStateResetPlugin`, `AppStateReset.install()`) lists each category in the
/// drawer. In a release build, a sidecar asks the receiver through the capability
/// `DebugDrawerReceiverCapability.appStateReset(_:)`, over the categories the host allows
/// (``AppStateResetRequests``), and the app clears them as it next comes to the foreground.
public enum AppStateReset {
    /// Cleanup of the app's own, run first when its category is selected, before any file is
    /// deleted, such as closing a database the app holds open, or clearing what the app keeps in
    /// memory.
    public struct Cleanup: Sendable {
        /// What the cleanup clears, as the drawer and a sidecar list it ("Close the orders
        /// database").
        public let title: String
        package let perform: @MainActor @Sendable () async throws -> Void

        /// - Parameters:
        ///   - title: What the cleanup clears, as the drawer and a sidecar list it.
        ///   - perform: The cleanup. An error it throws is shown with the reset's results.
        public init(_ title: String, perform: @escaping @MainActor @Sendable () async throws -> Void) {
            self.title = title
            self.perform = perform
        }
    }
}
