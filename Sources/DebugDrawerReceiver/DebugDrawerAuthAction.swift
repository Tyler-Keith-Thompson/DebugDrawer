import Foundation

/// An action on the app's own sign-in that a sidecar can ask for, to test how the app handles an
/// auth edge case in a release build: expire the access token, force a refresh, log out, or one
/// the host defines.
///
/// The action is the host's code: the library holds no token, reads none and passes none. A
/// sidecar sees only the action's ID, title and summary, and what the last run of it came to.
///
/// ```swift
/// receiver.enable(.authActions([
///     .expireAccessToken {
///         auth.expireAccessToken()
///         return .succeeded
///     },
///     .forceRefresh { await auth.refresh() ? .succeeded : .failed("The server refused the refresh token") },
///     DebugDrawerAuthAction("revoke-refresh-token", title: "Revoke Refresh Token") {
///         await auth.revokeRefreshToken() ? .succeeded : .failed("The server didn't answer")
///     }
/// ]))
/// ```
public struct DebugDrawerAuthAction: Identifiable {
    /// What an action came to, as the host's handler returns it.
    ///
    /// A failure's message is a `StaticString`, text written in the app's source, so no value the
    /// app holds at run time (a token, a server's answer, an account's details) can reach a
    /// sidecar through it. Say what went wrong in words a tester reads ("Not signed in"), never a
    /// credential written into the source.
    public enum Outcome: Sendable {
        /// The action did what it says.
        case succeeded
        /// The action didn't, for the reason `message` gives; the sidecar shows its first
        /// ``DebugDrawerAuthActions/Run/maximumMessageLength`` characters.
        case failed(StaticString)
    }

    /// The ID a sidecar asks for it by.
    public let id: String
    /// The name a sidecar lists it under.
    public let title: String
    /// What it does, as a sidecar shows it under the title; empty for none.
    public let summary: String
    /// Does it, on the main actor, and says what it came to.
    let handler: @MainActor () async -> Outcome

    /// An action of the host's own, such as revoking the refresh token or ending the session on
    /// the server.
    ///
    /// - Parameters:
    ///   - id: The ID a sidecar asks for it by; it must differ from every other action's.
    ///   - title: The name a sidecar lists it under.
    ///   - summary: What it does, shown under the title.
    ///   - handler: The host's code that does it, on the main actor, once per request, returning
    ///     what it came to. It receives nothing from the sidecar.
    public init(_ id: String, title: String, summary: String = "", handler: @escaping @MainActor () async -> Outcome) {
        self.id = id
        self.title = title
        self.summary = summary
        self.handler = handler
    }

    /// Expires the access token the app holds, so its next request meets the server's "expired"
    /// answer and the app's refresh path runs. ID `expire-access-token`.
    ///
    /// - Parameters:
    ///   - summary: What it does, shown under the title.
    ///   - handler: The host's code that marks its access token expired (or replaces it with one
    ///     the server will refuse), returning what it came to.
    /// - Returns: The action, titled "Expire Access Token".
    public static func expireAccessToken(
        summary: String = "The next request meets an expired token",
        handler: @escaping @MainActor () async -> Outcome
    ) -> Self {
        Self("expire-access-token", title: "Expire Access Token", summary: summary, handler: handler)
    }

    /// Refreshes the app's tokens now, as it would when the access token expires. ID
    /// `force-refresh`.
    ///
    /// - Parameters:
    ///   - summary: What it does, shown under the title.
    ///   - handler: The host's code that runs its refresh, returning what it came to.
    /// - Returns: The action, titled "Force Token Refresh".
    public static func forceRefresh(
        summary: String = "Refreshes the tokens now",
        handler: @escaping @MainActor () async -> Outcome
    ) -> Self {
        Self("force-refresh", title: "Force Token Refresh", summary: summary, handler: handler)
    }

    /// Logs the app out, as its own Log Out would. ID `log-out`.
    ///
    /// - Parameters:
    ///   - summary: What it does, shown under the title.
    ///   - handler: The host's code that logs out, returning what it came to.
    /// - Returns: The action, titled "Log Out".
    public static func logOut(
        summary: String = "Signs the app out, as its own Log Out does",
        handler: @escaping @MainActor () async -> Outcome
    ) -> Self {
        Self("log-out", title: "Log Out", summary: summary, handler: handler)
    }
}
