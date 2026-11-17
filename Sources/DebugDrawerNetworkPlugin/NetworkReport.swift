#if DEBUG
    import DebugDrawer
    import Foundation

    extension NetworkPlugin: DebugDrawerReportContributor {
        /// Adds every captured request and WebSocket connection as `network.har`.
        public func contribute(to report: inout DebugDrawerReport, redaction: DebugDrawerRedaction) {
            Self.contribute(NetworkStore.shared.entries, webSockets: NetworkStore.shared.webSockets, to: &report, redaction: redaction)
        }

        /// Adds `entries` and `webSockets` as an HTTP Archive, `network.har`, oldest first, with
        /// what `redaction` calls sensitive masked. Neither adds nothing.
        static func contribute(
            _ entries: [NetworkEntry],
            webSockets: [NetworkWebSocketConnection] = [],
            to report: inout DebugDrawerReport,
            redaction: DebugDrawerRedaction
        ) {
            guard !entries.isEmpty || !webSockets.isEmpty else { return }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            // The archive is strings, numbers and arrays of them, so encoding it can't fail.
            guard let har = try? encoder.encode(HTTPArchive(entries, webSockets: webSockets, redaction: redaction)) else { return }
            report.add(har: har, named: "network.har")
        }
    }
#endif
