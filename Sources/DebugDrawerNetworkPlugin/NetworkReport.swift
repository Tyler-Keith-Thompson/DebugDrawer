import DebugDrawer
import Foundation

extension NetworkPlugin: DebugDrawerReportContributor {
    /// Adds every captured request and WebSocket connection as `network.har`, and the newest
    /// session an earlier launch kept as `network-previous.har`: after a crash, the requests
    /// that led up to it. A plugin over a transport adds the requests and connections its latest
    /// snapshot captured, as `network.har`. Release builds capture nothing, so it adds nothing
    /// there.
    public func contribute(to report: inout DebugDrawerReport, redaction: DebugDrawerRedaction) {
        #if DEBUG
            if let transport {
                let log = transport.snapshot.log
                Self.contribute(log.captured, webSockets: log.webSockets, to: &report, redaction: redaction)
                return
            }
            let store = (model ?? .shared).store
            Self.contribute(store.entries, webSockets: store.webSockets, to: &report, redaction: redaction)
            // Read here, on the main actor, as the report is built now: a session is at most the
            // size limit, 20 MB unless the app set another.
            Self.contribute(previous: store.recorder?.newestPreviousSession(), to: &report)
        #endif
    }
}

#if DEBUG
    extension NetworkPlugin {
        /// Adds `entries` and `webSockets` as an HTTP Archive, `network.har`, oldest first, with
        /// what `redaction` calls sensitive masked. Neither adds nothing.
        nonisolated static func contribute(
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

        /// Adds the entries of `previous`, an earlier launch's session, as an HTTP Archive,
        /// `network-previous.har`, in the order they were written. They were masked as they were
        /// written, by the rules of that launch. No session, or one with no entries, adds nothing.
        nonisolated static func contribute(previous: NetworkSessionLog?, to report: inout DebugDrawerReport) {
            guard let previous, !previous.archiveEntries.isEmpty else { return }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            // The archive is strings, numbers and arrays of them, so encoding it can't fail.
            guard let har = try? encoder.encode(HTTPArchive(log: HTTPArchive.Log(entries: previous.archiveEntries))) else { return }
            report.add(har: har, named: "network-previous.har")
        }
    }
#endif
