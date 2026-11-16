#if DEBUG
    import DebugDrawer

    extension AnalyticsEvent {
        /// The event with each property value `redaction` calls sensitive replaced by its mask:
        /// a value under a key that contains one of its key patterns, at any depth, and one at a
        /// JSON path from the event's JSON (`properties.user.email`; arrays are transparent).
        /// The name, source and time are kept: they describe the event, not the user.
        func redacted(by redaction: DebugDrawerRedaction) -> AnalyticsEvent {
            let paths = redaction.jsonPaths.map { $0.split(separator: ".").map(String.init) }
            return AnalyticsEvent(
                id: id, timestamp: timestamp, name: name,
                properties: properties.redacted(at: ["properties"], by: redaction, paths: paths),
                source: source
            )
        }
    }

    // The rules are walked here, over the values themselves, rather than through
    // `DebugDrawerRedaction.redacting(json:)`: that re-encodes the document with JSONSerialization,
    // which writes 29.99 as 29.989999999999998 and drops the indentation. The path matching below
    // repeats core's few lines, which are private to it.
    extension [String: AnalyticsValue] {
        fileprivate func redacted(at path: [String], by redaction: DebugDrawerRedaction, paths: [[String]]) -> Self {
            Dictionary(uniqueKeysWithValues: map { key, value in
                let keyPath = path + [key]
                if redaction.masksKey(key) || paths.contains(where: { $0.matches(keyPath) }) {
                    return (key, AnalyticsValue.string(DebugDrawerRedaction.mask))
                }
                return (key, value.redacted(at: keyPath, by: redaction, paths: paths))
            })
        }
    }

    extension AnalyticsValue {
        fileprivate func redacted(at path: [String], by redaction: DebugDrawerRedaction, paths: [[String]]) -> AnalyticsValue {
            switch self {
            case let .object(object): .object(object.redacted(at: path, by: redaction, paths: paths))
            case let .array(elements): .array(elements.map { $0.redacted(at: path, by: redaction, paths: paths) })
            default: self
            }
        }
    }

    extension [String] {
        /// Whether this JSON path (components, `*` for any key) names the given key path.
        fileprivate func matches(_ keyPath: [String]) -> Bool {
            count == keyPath.count && zip(self, keyPath).allSatisfy { $0 == "*" || $0 == $1 }
        }
    }
#endif
