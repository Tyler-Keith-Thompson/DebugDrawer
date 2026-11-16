#if DEBUG
    import CoreTransferable
    import Foundation
    import UniformTypeIdentifiers

    /// A payload as a JSON file to share or save: its formatted JSON, named by its kind and period.
    struct MetricKitPayloadFile: Transferable, Sendable {
        let payload: MetricKitPayload

        static var transferRepresentation: some TransferRepresentation {
            // Written when the share sheet asks for it, so nothing lands on disk until then.
            DataRepresentation(exportedContentType: .json) { file in
                file.payload.formattedJSONData
            }
            .suggestedFileName { $0.payload.exportFileName }
        }
    }
#endif
