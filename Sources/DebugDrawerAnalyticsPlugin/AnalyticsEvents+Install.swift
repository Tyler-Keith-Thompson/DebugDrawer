import DebugDrawerAnalytics

public extension AnalyticsEvents {
    /// A capacity the Analytics plugin can't take: below 1.
    struct InvalidCapacity: Error, Equatable, Sendable {}

    /// Adds the Analytics plugin, keeping `defaultCapacity` events: in debug builds only; in
    /// release it does nothing.
    ///
    /// As `install(capacity:)` does with `defaultCapacity`.
    @MainActor
    static func install() {
        #if DEBUG
            AnalyticsEventsInstallation.install(capacity: defaultCapacity)
        #endif
    }

    /// Adds the Analytics plugin: in debug builds only; in release it does nothing.
    ///
    /// Events recorded before it are kept, so the ones an app sends while it launches show too.
    /// Calling it again replaces the plugin, keeping the events, the newest `capacity` of them.
    ///
    /// - Parameter capacity: How many events are kept; once full, each new event drops the
    ///   oldest.
    /// - Throws: `InvalidCapacity` when `capacity` is below 1, installing nothing. Release
    ///   builds install nothing and throw nothing.
    @MainActor
    static func install(capacity: Int) throws(InvalidCapacity) {
        #if DEBUG
            guard capacity > 0 else { throw InvalidCapacity() }
            AnalyticsEventsInstallation.install(capacity: capacity)
        #endif
    }
}
