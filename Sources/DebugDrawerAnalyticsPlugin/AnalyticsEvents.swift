import Foundation

/// The analytics events the app sends, in the debug drawer: each with its time and properties,
/// newest first, searchable, and exported as JSON, so QA can check the right event fired with the
/// right properties.
///
/// The app forwards each event where it hands it to its analytics service:
///
/// ```swift
/// AnalyticsEvents.record("checkout_completed", properties: ["plan": "pro", "seats": 3], source: "Segment")
/// ```
///
/// The type exists in every build, so the calls compile unchanged in release, where they do
/// nothing: ``record(_:properties:source:)`` doesn't even evaluate its arguments there.
public enum AnalyticsEvents {
    /// How many events are kept unless ``install(capacity:)`` is given another number.
    public static let defaultCapacity = 1000

    /// Adds the Analytics plugin: in debug builds only; in release it does nothing.
    ///
    /// Events recorded before it are kept, so the ones an app sends while it launches show too.
    /// Calling it again replaces the plugin, keeping the events, the newest `capacity` of them.
    ///
    /// - Parameter capacity: How many events are kept; once full, each new event drops the
    ///   oldest.
    /// - Precondition: `capacity` is at least 1.
    @MainActor
    public static func install(capacity: Int = defaultCapacity) {
        #if DEBUG
            precondition(capacity > 0, "AnalyticsEvents keeps at least one event")
            AnalyticsEventsInstallation.install(capacity: capacity)
        #endif
    }

    /// Records an event as the app sends it to its analytics service, at the time of the call:
    /// in debug builds only. In release it does nothing and evaluates none of its arguments.
    ///
    /// Call it from any thread or actor; it returns at once. Before ``install(capacity:)`` the
    /// newest ``defaultCapacity`` events are kept for the plugin to show once installed.
    ///
    /// - Parameters:
    ///   - name: The event's name (`checkout_completed`).
    ///   - properties: Its properties, as the service is sent them.
    ///   - source: Which service or SDK it is sent to (`Segment`), when the app sends to more
    ///     than one; `nil` for none.
    /// - Complexity: O(1), amortized.
    public static func record(
        _ name: @autoclosure () -> String,
        properties: @autoclosure () -> [String: AnalyticsValue] = [:],
        source: @autoclosure () -> String? = nil
    ) {
        #if DEBUG
            AnalyticsEventLog.shared.record(name: name(), properties: properties(), source: source())
        #endif
    }
}
