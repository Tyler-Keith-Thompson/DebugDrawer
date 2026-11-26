import Foundation

// A key and a closure, not a value: the closure is asked each time the state is read (as a session
// opens, on the sidecar's refresh, for a bug report), so the sidecar sees the value as it is then,
// and nothing is read while no one is debugging. Keys that look like secrets ("token", "password")
// are not refused: a name says nothing about the value under it (a key named "plan" can still be
// handed a token), so a refusal would only teach hosts to rename keys. The host is told instead,
// here and in the receiver's AppStateInReports article, never to register a secret. A field is
// made inline, in the host's list, so its key is checked where the list is handed over
// (`DebugDrawerAppState` throws), and the list takes no `try` per field.

/// A value of the host's own that the app state capability shows a sidecar beside the build: a
/// key, and a closure that reads the value as the state is read.
///
/// ```swift
/// DebugDrawerAppStateField("plan") { .string(account.plan.rawValue) }
/// DebugDrawerAppStateField("cartItems") { .number(Double(cart.items.count)) }
/// ```
///
/// What the closure returns leaves the process: never register a secret (a token, a password, a
/// keychain value) or a raw identifier of a person (an email address, a user ID; hand the user ID
/// to ``DebugDrawerAppState`` instead, which hashes it). Keys aren't checked for what they look
/// like, so nothing stops a field named `token`: the host decides what it registers.
@MainActor
public struct DebugDrawerAppStateField {
    /// The name the sidecar shows the value under. Unique among the fields.
    public let key: String
    /// Reads the value now; `nil` leaves it out of this reading.
    let value: @MainActor () -> DebugDrawerAppStateValue?

    /// A field under `key`, read by `value` each time the state is read.
    ///
    /// - Parameters:
    ///   - key: The name the sidecar shows the value under: not empty, and unique among the
    ///     state's fields, or ``DebugDrawerAppState`` throws as it is made.
    ///   - value: Reads the value: a string, a number or a Boolean, or `nil` to leave it out.
    public init(_ key: String, value: @escaping @MainActor () -> DebugDrawerAppStateValue?) {
        self.key = key
        self.value = value
    }
}
