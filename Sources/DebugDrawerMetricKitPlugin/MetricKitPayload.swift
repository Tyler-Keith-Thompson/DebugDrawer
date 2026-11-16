#if DEBUG
    import Foundation

    /// One payload MetricKit delivered: its kind, the period it covers, when it arrived, and its
    /// JSON, with sorted keys.
    struct MetricKitPayload: Codable, Equatable, Identifiable, Sendable {
        let id: UUID
        let kind: MetricKitPayloadKind
        /// The start of the period the payload covers.
        let begin: Date
        /// The end of the period the payload covers.
        let end: Date
        /// When the app received it.
        let received: Date
        /// The payload's JSON object, compact, keys sorted.
        let json: Data
        /// Whether the developer has opened the payload in the drawer.
        var isSeen: Bool
    }

    extension MetricKitPayload {
        /// The JSON indented, keys sorted, as the drawer shows, exports and reports it.
        var formattedJSONData: Data {
            // The JSON was an object when it was kept, so it parses and writes again; the compact
            // form stands in should the file have been changed under the store.
            guard let object = try? JSONSerialization.jsonObject(with: json),
                  let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            else { return json }
            return data
        }

        /// ``formattedJSONData`` as text.
        var formattedJSON: String {
            String(bytes: formattedJSONData, encoding: .utf8) ?? ""
        }

        /// What the payload holds, in a line.
        var summary: MetricKitPayloadSummary {
            MetricKitPayloadSummary(kind: kind, json: json)
        }

        /// The name the payload is exported under: its kind and the end of its period
        /// (`MetricKit metrics 2025-11-16T00-00-00Z.json`).
        var exportFileName: String {
            "MetricKit \(reportName).json"
        }

        /// The name the payload has in a bug report, without the extension: its kind and the end
        /// of its period, the colons a file name can't hold as dashes.
        var reportName: String {
            "\(kind.rawValue) \(end.formatted(.iso8601).replacing(":", with: "-"))"
        }

        /// The period the payload covers, ordered even if the timestamps it named weren't.
        var period: Range<Date> {
            min(begin, end) ..< max(begin, end)
        }
    }

    extension MetricKitPayloadKind {
        /// How the drawer names it.
        var title: String {
            switch self {
            case .metrics: "Metrics"
            case .diagnostics: "Diagnostics"
            }
        }
    }
#endif
