#if DEBUG
    import Foundation

    /// What a session kept on disk holds, read back: its header, its requests as the log shows
    /// them, and the archive entries they were read from.
    struct NetworkSessionLog: Sendable {
        let summary: NetworkSessionSummary
        /// The file's header; `nil` when its first line isn't one, as when the file was deleted
        /// and started again partway through the session.
        let header: NetworkSessionHeader?
        /// The entries as they were written, for a bug report's archive, oldest first.
        let archiveEntries: [HTTPArchive.Entry]
        /// The requests, and the WebSocket connections as their handshakes, the newest first, as
        /// the log lists captured ones.
        let entries: [NetworkEntry]
        /// How many lines couldn't be read: a last line the app was writing when it ended, torn,
        /// or a line in a format this build doesn't read.
        let skippedLines: Int

        /// The session in `data`, the contents of the file `summary` names. A line that isn't
        /// JSON of an entry is skipped, so a session cut short mid-line reads up to that line; a
        /// file whose header names a later format reads as empty.
        init(summary: NetworkSessionSummary, data: Data) {
            self.summary = summary
            let decoder = JSONDecoder()
            var lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)[...]
            let header = lines.first.flatMap { try? decoder.decode(NetworkSessionHeader.self, from: Data($0)) }
            if header != nil {
                lines = lines.dropFirst()
            }
            guard (header?.format ?? NetworkSessionHeader.currentFormat) <= NetworkSessionHeader.currentFormat else {
                self.header = header
                archiveEntries = []
                entries = []
                skippedLines = lines.count
                return
            }
            let decoded = lines.map { try? decoder.decode(HTTPArchive.Entry.self, from: Data($0)) }
            self.header = header
            archiveEntries = decoded.compactMap(\.self)
            entries = archiveEntries.map(NetworkEntry.init).sorted { $0.timestamp > $1.timestamp }
            skippedLines = decoded.count(where: { $0 == nil })
        }
    }
#endif
