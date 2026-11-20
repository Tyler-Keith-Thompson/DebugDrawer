#if DEBUG
    import Foundation

    // `package`, not public: the Analytics plugin's drawer reads the debug build's log of these,
    // and nothing outside this package needs them. A sidecar sees `AnalyticsEventsMirror.Event`,
    // which a release build has too.

    /// One event the app recorded: when, its name, its properties and the service it went to.
    package struct AnalyticsEvent: Equatable, Identifiable, Sendable {
        /// Its place in the order events were recorded, from 1: a later event has a larger one.
        package let id: Int
        package let timestamp: Date
        package let name: String
        package let properties: [String: AnalyticsValue]
        /// The service or SDK it was sent to, if the app named one.
        package let source: String?

        /// An event.
        package init(id: Int, timestamp: Date, name: String, properties: [String: AnalyticsValue], source: String?) {
            self.id = id
            self.timestamp = timestamp
            self.name = name
            self.properties = properties
            self.source = source
        }
    }
#endif
