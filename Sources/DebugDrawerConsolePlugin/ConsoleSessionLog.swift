#if DEBUG
    import Foundation

    /// What a session kept on disk holds, read back: its header and its log lines.
    struct ConsoleSessionLog: Equatable, Codable, Sendable {
        let summary: ConsoleSessionSummary
        /// The file's header; `nil` when its first line isn't one, as when the file was deleted
        /// and started again partway through the session.
        let header: ConsoleSessionHeader?
        /// The lines, oldest first, as the console lists captured ones.
        let lines: [LogLine]
        /// How many lines couldn't be read: a last line the app was writing when it ended, torn,
        /// or a line in a format this build doesn't read.
        let skippedLines: Int

        /// The session in `data`, the contents of the file `summary` names. A line that isn't
        /// JSON of a log line is skipped, so a session cut short mid-line reads up to that line;
        /// a file whose header names a later format reads as empty.
        init(summary: ConsoleSessionSummary, data: Data) {
            self.summary = summary
            let decoder = JSONDecoder()
            var rows = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)[...]
            let header = rows.first.flatMap { try? decoder.decode(ConsoleSessionHeader.self, from: Data($0)) }
            if header != nil {
                rows = rows.dropFirst()
            }
            self.header = header
            guard (header?.format ?? ConsoleSessionHeader.currentFormat) <= ConsoleSessionHeader.currentFormat else {
                lines = []
                skippedLines = rows.count
                return
            }
            let decoded = rows.map { (try? decoder.decode(ConsoleSessionLine.self, from: Data($0)))?.logLine }
            lines = decoded.compactMap(\.self)
            skippedLines = decoded.count(where: { $0 == nil })
        }
    }
#endif
