import Foundation

// The sink lives here, in the UI-free module a release build links, rather than in the plugin: a
// release build that mirrors events to a sidecar calls the same `record` its debug build does. In
// a debug build `record` also keeps each event in the log the Analytics plugin's drawer shows;
// in any build it hands each one to the mirrors of the sidecar sessions open now, and when none is
// open, a release build evaluates none of its arguments.

/// The analytics events the app sends: kept for the Analytics plugin's drawer in debug builds, and
/// mirrored, redacted, to a sidecar while one of its sessions is open, in any build whose receiver
/// enables `DebugDrawerReceiverCapability.analyticsEvents(sessions:redaction:capacity:)`.
///
/// The app forwards each event where it hands it to its analytics service:
///
/// ```swift
/// AnalyticsEvents.record("checkout_completed", properties: ["plan": "pro", "seats": 3], source: "Segment")
/// ```
///
/// The type exists in every build, so the calls compile unchanged in release, where they do
/// nothing unless a sidecar's session is mirroring: ``record(_:properties:source:)`` doesn't even
/// evaluate its arguments then.
public enum AnalyticsEvents {
    /// How many events are kept unless the Analytics plugin's `install(capacity:)` is given another
    /// number.
    public static let defaultCapacity = 1000

    /// Records an event as the app sends it to its analytics service, at the time of the call.
    ///
    /// In a debug build the event is kept for the Analytics plugin; before its `install` the newest
    /// ``defaultCapacity`` events are kept for the plugin to show once installed. While a sidecar's
    /// session is open and the receiver mirrors analytics events, the event is also redacted and
    /// mirrored to it, in any build. Otherwise, in release, it does nothing and evaluates none of
    /// its arguments.
    ///
    /// Call it from any thread or actor; it returns at once.
    ///
    /// - Parameters:
    ///   - name: The event's name (`checkout_completed`).
    ///   - properties: Its properties, as the service is sent them.
    ///   - source: Which service or SDK it is sent to (`Segment`), when the app sends to more
    ///     than one; `nil` for none.
    /// - Complexity: O(1), amortized, while no session mirrors; O(*n*) in the size of the
    ///   properties while one does, to redact them.
    public static func record(
        _ name: @autoclosure () -> String,
        properties: @autoclosure () -> [String: AnalyticsValue] = [:],
        source: @autoclosure () -> String? = nil
    ) {
        #if DEBUG
            let name = name(), properties = properties(), source = source()
            AnalyticsEventLog.shared.record(name: name, properties: properties, source: source)
            AnalyticsMirrorInboxes.shared.deliver(name: name, properties: properties, source: source)
        #else
            guard AnalyticsMirrorInboxes.shared.isMirroring else { return }
            AnalyticsMirrorInboxes.shared.deliver(name: name(), properties: properties(), source: source())
        #endif
    }
}
