#if DEBUG
    import Foundation

    extension AnalyticsEvent {
        /// Whether the event matches what was typed in the filter field: its name, its source, a
        /// property's key or a property's value contains `query`, nested keys and values
        /// included, ignoring case and diacritics. Values are matched as the drawer shows them
        /// (`true`, `3`, `2026-11-16T10:46:40.000Z`). An empty query, or one of spaces, matches
        /// every event.
        func matches(_ query: String) -> Bool {
            let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return true }
            return name.containsIgnoringCase(query)
                || source?.containsIgnoringCase(query) == true
                || properties.contains { key, value in key.containsIgnoringCase(query) || value.matches(query) }
        }
    }

    extension AnalyticsValue {
        /// Whether the value, or a key or value nested in it, contains `query`.
        fileprivate func matches(_ query: String) -> Bool {
            switch self {
            case let .array(elements):
                elements.contains { $0.matches(query) }
            case let .object(object):
                object.contains { key, value in key.containsIgnoringCase(query) || value.matches(query) }
            default:
                displayText.containsIgnoringCase(query)
            }
        }
    }

    extension String {
        fileprivate func containsIgnoringCase(_ other: String) -> Bool {
            range(of: other, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }
#endif
