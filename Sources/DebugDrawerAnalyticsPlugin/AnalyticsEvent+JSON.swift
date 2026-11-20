#if DEBUG
    import DebugDrawer
    import Foundation

    extension AnalyticsEvent {
        /// The event as JSON, indented, keys sorted: its `name`, its `properties`, its `source`
        /// when it has one and its `timestamp`, dates in ISO 8601 with milliseconds.
        var formattedJSON: String {
            Self.formattedJSON(of: AnalyticsEventJSON(self))
        }

        /// ``formattedJSON`` of the event ``redacted(by:)`` `redaction`.
        func formattedJSON(redaction: DebugDrawerRedaction) -> String {
            redacted(by: redaction).formattedJSON
        }

        /// The events as a JSON array, in the order given, formatted as ``formattedJSON``, each
        /// ``redacted(by:)`` `redaction`.
        static func formattedJSON(of events: [AnalyticsEvent], redaction: DebugDrawerRedaction) -> String {
            formattedJSON(of: events.map { AnalyticsEventJSON($0.redacted(by: redaction)) })
        }

        private static func formattedJSON(of value: some Encodable) -> String {
            encoded(value, formatting: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        }

        private static func encoded(_ value: some Encodable, formatting: JSONEncoder.OutputFormatting) -> String {
            let encoder = JSONEncoder()
            encoder.outputFormatting = formatting
            // JSON has no infinity or NaN; written as strings, every Double encodes.
            encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
            encoder.dateEncodingStrategy = .custom { date, encoder in
                var container = encoder.singleValueContainer()
                try container.encode(date.formatted(AnalyticsEventJSON.dateStyle))
            }
            // Strings, numbers, Booleans, nulls, arrays and objects of them always encode: the
            // only failure JSONEncoder has for them, a non-finite number, is written as a string.
            // JSONEncoder writes UTF-8.
            return (try? encoder.encode(value)).flatMap { String(bytes: $0, encoding: .utf8) } ?? "null"
        }
    }

    /// An event as it is written in JSON.
    struct AnalyticsEventJSON: Encodable {
        /// ISO 8601 with milliseconds, in UTC: events sent in one second still read in order.
        static let dateStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

        let name: String
        let properties: [String: AnalyticsValueJSON]
        let source: String?
        let timestamp: Date

        init(_ event: AnalyticsEvent) {
            name = event.name
            properties = event.properties.mapValues(AnalyticsValueJSON.init)
            source = event.source
            timestamp = event.timestamp
        }
    }

    /// A property's value as it is written in JSON: dates as ISO 8601 strings.
    ///
    /// A wrapper rather than `AnalyticsValue`'s own `Codable` conformance, which keys each value by
    /// its case so a sidecar decodes exactly what was recorded; the drawer's JSON is the bare
    /// values a person reads.
    struct AnalyticsValueJSON: Encodable {
        let value: AnalyticsValue

        func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            switch value {
            case let .string(string): try container.encode(string)
            case let .int(int): try container.encode(int)
            case let .double(double): try container.encode(double)
            case let .bool(bool): try container.encode(bool)
            case let .date(date): try container.encode(date)
            case .null: try container.encodeNil()
            case let .array(array): try container.encode(array.map(Self.init))
            case let .object(object): try container.encode(object.mapValues(Self.init))
            }
        }
    }

    extension AnalyticsValue {
        /// The value as the drawer shows it beside its key and searches it: a string as itself,
        /// a number or a Boolean as JSON writes it, a date in ISO 8601, `null`, and an array or
        /// object as compact JSON with sorted keys.
        var displayText: String {
            switch self {
            case let .string(string): string
            case let .date(date): date.formatted(AnalyticsEventJSON.dateStyle)
            default: AnalyticsEvent.compactJSON(of: AnalyticsValueJSON(value: self))
            }
        }
    }

    extension AnalyticsEvent {
        /// `value` as compact JSON, keys sorted.
        static func compactJSON(of value: some Encodable) -> String {
            encoded(value, formatting: [.sortedKeys, .withoutEscapingSlashes])
        }
    }
#endif
