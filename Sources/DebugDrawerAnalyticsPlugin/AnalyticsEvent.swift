#if DEBUG
    import Foundation

    /// One event the app recorded: when, its name, its properties and the service it went to.
    struct AnalyticsEvent: Equatable, Identifiable, Sendable {
        /// Its place in the order events were recorded, from 1: a later event has a larger one.
        let id: Int
        let timestamp: Date
        let name: String
        let properties: [String: AnalyticsValue]
        /// The service or SDK it was sent to, if the app named one.
        let source: String?
    }

    extension AnalyticsEvent {
        /// The property keys, sorted, as the drawer lists them.
        var sortedKeys: [String] {
            properties.keys.sorted()
        }

        /// What the event carries, in a line: `Segment · 3 properties`, `No properties`.
        var summary: String {
            let count = switch properties.count {
            case 0: "No properties"
            case 1: "1 property"
            default: "\(properties.count) properties"
            }
            return [source, count].compactMap(\.self).joined(separator: " · ")
        }
    }
#endif
