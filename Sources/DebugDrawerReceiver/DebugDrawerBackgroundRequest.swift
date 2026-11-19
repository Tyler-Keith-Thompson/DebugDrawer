// What `DebugDrawerBackgroundKeeper` holds to keep the app reachable, as a plain value: a host
// shows it beside its session indicator, and a test compares it. Real in every build: a value does
// nothing by itself, and in release the keeper's is always `none`.

/// What a ``DebugDrawerBackgroundKeeper`` holds of the platform to keep the app running while a
/// sidecar's session is open.
public enum DebugDrawerBackgroundRequest: Equatable, Sendable {
    /// Nothing: no session is open, the platform has nothing to ask for (watchOS), or the system
    /// ended the last request and the app hasn't come back to the foreground since.
    case none
    /// A UIKit background task (`beginBackgroundTask(withName:expirationHandler:)`) on iOS, iPadOS,
    /// tvOS and visionOS: a short handoff, about 30 seconds once the app is in the background,
    /// shown by no system indicator.
    case backgroundTask
    /// A `BGContinuedProcessingTask` on iOS and iPadOS 26 and later, started from a person's action
    /// with ``DebugDrawerBackgroundKeeper/startSession(duration:title:subtitle:)``: the system
    /// shows its progress, and the person can stop it there.
    case continuedProcessing
    /// A `ProcessInfo` activity on macOS and Mac Catalyst, which keeps App Nap from slowing the app
    /// while it is in the background.
    case activity
}
