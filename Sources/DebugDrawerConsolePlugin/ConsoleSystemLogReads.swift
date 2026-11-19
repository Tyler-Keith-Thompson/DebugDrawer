#if DEBUG
    import Foundation

    /// The reads of the system's log that complete one earlier session, merged, and whether
    /// another is needed.
    ///
    /// Under load one read of `OSLogStore(scope: .system)` can miss an entry the store holds, which
    /// an earlier or a later read returns. So a launch that logged nothing more can't be told from
    /// a read that missed what it logged by one read alone. Two signals tell them apart:
    /// - **The session's own last os_log line.** The process read it from the log before it
    ///   ended, so the store holds it, and every read starts just before it: a read that lacks it
    ///   is known to be incomplete.
    /// - **Agreement.** A read that holds that line and finds nothing the reads before it lacked
    ///   settles the lines. A missed line shows up as one read holding what another didn't, and is
    ///   kept from whichever read held it; a launch that logged nothing gives the same lines each
    ///   time.
    ///
    /// The reads stop once settled, or after ``maxReads``, whichever comes first; there is no
    /// wait between them.
    struct ConsoleSystemLogReads {
        /// The most reads made for one session: each takes a second or more, and listing the
        /// earlier sessions waits for them.
        static let maxReads = 4

        /// What makes two lines of different reads the same entry of the system's log.
        private struct Entry: Hashable {
            let timestamp: Date
            let text: String
            let level: LogLine.Level
            let subsystem: String
            let category: String

            init(_ line: LogLine) {
                timestamp = line.timestamp
                text = line.text
                level = line.level
                subsystem = line.subsystem
                category = line.category
            }
        }

        private let tail: ConsoleSessionTail
        /// Every line any read returned, as many of each entry as the read holding the most of it,
        /// with the order it was added in, which breaks ties of time.
        private var merged: [(line: LogLine, order: Int)] = []
        private var counts: [Entry: Int] = [:]
        /// How many reads were added.
        private(set) var count = 0
        private var isSettled = false

        /// The reads for the session `tail` ends.
        init(_ tail: ConsoleSessionTail) {
            self.tail = tail
        }

        /// The lines any read returned, oldest first.
        var lines: [LogLine] {
            merged.sorted { ($0.line.timestamp, $0.order) < ($1.line.timestamp, $1.order) }.map(\.line)
        }

        /// Whether to read again: the reads haven't settled and fewer than ``maxReads`` were made.
        var needsAnother: Bool {
            !isSettled && count < Self.maxReads
        }

        /// Merges the lines of one more read.
        mutating func add(_ read: [LogLine]) {
            count += 1
            var seen: [Entry: Int] = [:]
            var foundNew = false
            for line in read {
                let entry = Entry(line)
                seen[entry, default: 0] += 1
                if seen[entry, default: 0] > counts[entry, default: 0] {
                    counts[entry] = seen[entry]
                    merged.append((line, merged.count))
                    foundNew = true
                }
            }
            isSettled = count > 1 && !foundNew && tail.holdsLastLine(read)
        }
    }
#endif
