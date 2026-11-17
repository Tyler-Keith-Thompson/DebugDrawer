#if DEBUG
    /// The lines a console text view has drawn, with where each starts in its text, and how to
    /// bring the text to a new list of lines with the least redrawing.
    ///
    /// A new list usually extends the drawn one: lines arrive at the end, and at capacity the
    /// oldest leave the start. Anything else (a filter or search that changed, another session)
    /// redraws every line. Lines are compared by identity, so a list of the same length with
    /// other lines, as when a mute changes at capacity, is never mistaken for the drawn one.
    struct ConsoleRenderedLines {
        /// How the text changes to show a new list of lines.
        enum Update: Equatable {
            /// The text shows the lines already.
            case none
            /// Delete the first `dropping` lines, then append the new list's lines from
            /// `appending` on.
            case extend(dropping: Int, appending: Int)
            /// Draw every line again.
            case redraw
        }

        /// The lines drawn, oldest first.
        private(set) var lines: [LogLine] = []
        /// Where each drawn line starts in the text, in UTF-16 code units, as `NSAttributedString`
        /// counts them.
        private(set) var starts: [Int] = []

        /// How to change the text from these lines to `newLines`.
        ///
        /// - Complexity: O(*n*) in the number of lines.
        func update(to newLines: [LogLine]) -> Update {
            guard !lines.isEmpty, let first = newLines.first else {
                return lines.isEmpty && newLines.isEmpty ? .none : .redraw
            }
            guard let dropped = lines.firstIndex(where: { $0.id == first.id }) else { return .redraw }
            let kept = lines.count - dropped
            guard newLines.count >= kept,
                  zip(lines[dropped...], newLines[..<kept]).allSatisfy({ $0.id == $1.id }) else { return .redraw }
            return dropped == 0 && kept == newLines.count ? .none : .extend(dropping: dropped, appending: kept)
        }

        /// Records that the text was drawn again: `lines`, the first starting at 0 and each next
        /// one at the offset in `starts`.
        mutating func redrew(_ lines: [LogLine], starts: [Int]) {
            self.lines = lines
            self.starts = starts
        }

        /// Records that the first `dropping` lines were deleted, which took the text's first
        /// `starts[dropping]` code units with them, and that `appended` were added with their
        /// starts in `appendedStarts`, already offset into the text.
        mutating func extended(dropping: Int, appended: [LogLine], appendedStarts: [Int]) {
            if dropping > 0 {
                let removed = starts[dropping]
                lines.removeFirst(dropping)
                starts = starts.dropFirst(dropping).map { $0 - removed }
            }
            lines += appended
            starts += appendedStarts
        }

        /// How many code units the first `dropping` lines take, with the newline after them.
        func length(ofFirst dropping: Int) -> Int {
            dropping < starts.count ? starts[dropping] : 0
        }

        /// The drawn line at `offset` in the text, a code unit in it or in the newline after it;
        /// `nil` when there are no lines.
        ///
        /// - Complexity: O(log *n*) in the number of lines.
        func line(at offset: Int) -> LogLine? {
            guard !lines.isEmpty else { return nil }
            var low = 0
            var high = starts.count - 1
            // The last line starting at or before the offset.
            while low < high {
                let middle = (low + high + 1) / 2
                if starts[middle] <= offset {
                    low = middle
                } else {
                    high = middle - 1
                }
            }
            return lines[low]
        }
    }
#endif
