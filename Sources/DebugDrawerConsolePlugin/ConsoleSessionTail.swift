#if DEBUG
    import Foundation

    /// Where an earlier session's os_log lines end: which process wrote it, and its last os_log
    /// line, after which the system's log may hold lines the session missed.
    struct ConsoleSessionTail: Equatable, Sendable {
        /// The session's name in the storage.
        let name: String
        /// The process that wrote the session.
        let processIdentifier: Int32
        /// The time of the session's last os_log line, or when it started if it kept none.
        let since: Date
        /// `since` as the session's file writes it, to the millisecond; `nil` when the session
        /// kept no os_log line.
        let lastTime: String?
        /// The texts of the os_log lines the session kept at `lastTime`.
        let textsAtLastTime: Set<String>
        /// Whether the session kept any line after its header.
        let holdsLines: Bool

        /// The tail of the session named `name` whose file holds `data`; `nil` when its header
        /// doesn't name its process.
        ///
        /// - Complexity: O(*n*) in the size of the file, decoding only the header and the lines
        ///   from the last os_log one on.
        init?(name: String, data: Data) {
            let decoder = JSONDecoder()
            let rows = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
            guard let first = rows.first,
                  let header = try? decoder.decode(ConsoleSessionHeader.self, from: Data(first)),
                  let processIdentifier = header.processIdentifier,
                  let started = try? ConsoleSessionHeader.dateStyle.parse(header.started) else { return nil }
            self.name = name
            self.processIdentifier = processIdentifier
            holdsLines = rows.count > 1
            // os_log lines reach the session in the order they were logged, between lines from
            // stdout and stderr, so the last ones logged are the last ones written.
            var lastTime: String?
            var texts: Set<String> = []
            // Only rows that name the source are decoded: a session of stdout lines alone is
            // scanned, not decoded, whole. The recorder writes keys sorted, without spaces.
            let marker = Data(#""source":"oslog""#.utf8)
            for row in rows.dropFirst().reversed() where row.firstRange(of: marker) != nil {
                guard let line = try? decoder.decode(ConsoleSessionLine.self, from: Data(row)),
                      line.source == LogLine.Source.oslog.rawValue else { continue }
                if lastTime == nil { lastTime = line.time }
                guard line.time == lastTime else { break }
                texts.insert(line.text)
            }
            self.lastTime = lastTime
            textsAtLastTime = texts
            since = lastTime.flatMap { try? ConsoleSessionHeader.dateStyle.parse($0) } ?? started
        }

        /// Whether `line`, from the system's log at or after `since`, is one the session missed:
        /// one logged after its last os_log line, or in the same millisecond with another text.
        func missed(_ line: LogLine) -> Bool {
            guard let lastTime else { return true }
            let time = ConsoleSessionHeader.dateStyle.format(line.timestamp)
            // Fixed-width ISO 8601 in UTC, so the strings order as the times do.
            return time > lastTime || (time == lastTime && !textsAtLastTime.contains(line.text))
        }

        /// Whether `lines`, a read of the system's log from `since`, hold the os_log lines the
        /// session kept at its last time, which the store holds as the process read them from it;
        /// `true` when the session kept no os_log line, as there is then nothing to look for.
        func holdsLastLine(_ lines: [LogLine]) -> Bool {
            guard let lastTime else { return true }
            let texts = Set(lines.lazy.filter { ConsoleSessionHeader.dateStyle.format($0.timestamp) == lastTime }.map(\.text))
            return textsAtLastTime.isSubset(of: texts)
        }
    }
#endif
