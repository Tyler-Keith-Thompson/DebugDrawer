#if DEBUG && !os(tvOS) && !os(watchOS)
    import CoreTransferable
    import DebugDrawer
    import Foundation
    import UniformTypeIdentifiers

    /// Every event as a JSON file to share or save: an array, the newest first, formatted as each
    /// event's JSON is, with what the redaction rules call sensitive masked.
    struct AnalyticsEventsFile: Transferable, Sendable {
        let events: [AnalyticsEvent]
        let redaction: DebugDrawerRedaction

        /// `Analytics Events <the newest event's time>.json`, the colons a file name can't hold as
        /// dashes.
        var fileName: String {
            let time = events.first.map { " " + $0.timestamp.formatted(.iso8601).replacing(":", with: "-") } ?? ""
            return "Analytics Events\(time).json"
        }

        /// What the file holds.
        var data: Data {
            Data(AnalyticsEvent.formattedJSON(of: events, redaction: redaction).utf8)
        }

        static var transferRepresentation: some TransferRepresentation {
            // Written when the share sheet asks for it, so nothing is encoded until then.
            DataRepresentation(exportedContentType: .json) { file in
                file.data
            }
            .suggestedFileName { $0.fileName }
        }
    }
#endif
