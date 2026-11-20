import DebugDrawerAnalytics

public extension AnalyticsEvents {
    /// Adds the Analytics plugin: in debug builds only; in release it does nothing.
    ///
    /// Events recorded before it are kept, so the ones an app sends while it launches show too.
    /// Calling it again replaces the plugin, keeping the events, the newest `capacity` of them.
    ///
    /// - Parameter capacity: How many events are kept; once full, each new event drops the
    ///   oldest.
    /// - Precondition: `capacity` is at least 1.
    @MainActor
    static func install(capacity: Int = defaultCapacity) {
        #if DEBUG
            precondition(capacity > 0, "AnalyticsEvents keeps at least one event")
            AnalyticsEventsInstallation.install(capacity: capacity)
        #endif
    }
}
