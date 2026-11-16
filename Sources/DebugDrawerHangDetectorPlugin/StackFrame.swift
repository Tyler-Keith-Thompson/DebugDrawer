#if DEBUG
    /// One line of a hang's stack read into its parts, as Xcode's debug navigator shows a frame:
    /// its index, the image it's in, and its symbol.
    ///
    /// The lines are `backtrace_symbols(3)`'s ("1   Example   0x0000000100004a1c
    /// $s7Example5crashyyF + 48"), or MetricKit's, which have no symbol ("1 Example 0x100004000 +
    /// 16384"). The Crash Reports plugin reads the same lines with a type of its own: the plugins are
    /// vertical, and a dozen lines cost less than a shared module.
    struct StackFrame: Equatable {
        let index: Int
        let image: String
        /// The function, without its offset; the address and offset when the line names none.
        let symbol: String

        /// The parts of `line`; a line that isn't in either form is its own symbol, at
        /// `position`, in an unknown image.
        init(line: String, position: Int) {
            let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count >= 3, let index = Int(parts[0]), parts[2].hasPrefix("0x") else {
                self.init(index: position, image: "???", symbol: line)
                return
            }
            let rest = parts.count > 3 ? parts[3].trimmingPrefix(while: \.isWhitespace) : ""
            let symbol = if rest.isEmpty || rest.hasPrefix("+") {
                // MetricKit's line: the address and its offset into the image are all it has.
                rest.isEmpty ? String(parts[2]) : "\(parts[2]) \(rest)"
            } else if let offset = rest.range(of: " + ", options: .backwards) {
                String(rest[..<offset.lowerBound])
            } else {
                String(rest)
            }
            self.init(index: index, image: String(parts[1]), symbol: symbol)
        }

        init(index: Int, image: String, symbol: String) {
            self.index = index
            self.image = image
            self.symbol = symbol
        }

        /// The frames of `lines`, innermost first.
        static func frames(_ lines: [String]) -> [StackFrame] {
            lines.enumerated().map { StackFrame(line: $1, position: $0) }
        }

        /// Whether the frame is in the app's own executable, named `ownImage`.
        func isOwnCode(_ ownImage: String?) -> Bool {
            image == ownImage
        }
    }
#endif
