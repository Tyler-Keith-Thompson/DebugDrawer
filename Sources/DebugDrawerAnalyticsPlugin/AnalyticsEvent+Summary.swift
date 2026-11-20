#if DEBUG
    import DebugDrawerAnalytics
    import Foundation

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
