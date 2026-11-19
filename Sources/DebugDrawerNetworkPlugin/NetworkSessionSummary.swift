#if DEBUG
    import Foundation

    /// A session kept on disk, as the list of sessions names it: when it started and how large it
    /// is, read from its file's name and size without opening it.
    struct NetworkSessionSummary: Identifiable, Hashable, Codable, Sendable {
        /// The file's name, `<start>-<UUID>.jsonl`.
        let id: String
        /// When the session started.
        let started: Date
        /// How many bytes its file holds.
        let byteCount: Int

        /// The summary of `file`, or `nil` when its name isn't one the plugin gives a session.
        init?(_ file: NetworkSessionFile) {
            guard let started = Self.started(fromName: file.name) else { return nil }
            id = file.name
            self.started = started
            byteCount = file.byteCount
        }

        /// The name of a session that starts at `started`, unique by `id`: the start in UTC to
        /// the millisecond, without colons, which a file name can't hold everywhere, so names sort
        /// as the sessions started.
        static func name(started: Date, id: UUID) -> String {
            "\(nameStyle.format(started))-\(id.uuidString).jsonl"
        }

        /// What the session menu lists: the start, to the second, and the size, `Nov 17, 10:42:05 AM · 48 KB`,
        /// in `locale` and `timeZone`, which a view takes from its environment.
        func title(locale: Locale, timeZone: TimeZone) -> String {
            var style = Date.FormatStyle.dateTime.month(.abbreviated).day().hour().minute().second().locale(locale)
            style.timeZone = timeZone
            return "\(started.formatted(style)) · \(byteCount.formatted(.byteCount(style: .file).locale(locale)))"
        }

        /// `2026-11-17T104205.123Z`: ISO 8601, fixed width, so names sort as the dates do.
        private static let nameStyle = Date.ISO8601FormatStyle(timeSeparator: .omitted, includingFractionalSeconds: true)

        private static func started(fromName name: String) -> Date? {
            // The start is the name's first 22 characters: `yyyy-MM-ddTHHmmss.SSSZ`.
            guard name.hasSuffix(".jsonl"), name.count > 22 else { return nil }
            return try? nameStyle.parse(String(name.prefix(22)))
        }
    }
#endif
