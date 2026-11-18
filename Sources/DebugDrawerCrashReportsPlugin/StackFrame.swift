#if DEBUG
    /// One line of a report's stack read into its parts, as Xcode's debug navigator shows a frame:
    /// its index, the image it's in, and its symbol.
    ///
    /// The lines are `backtrace_symbols(3)`'s, the image padded to a column ("1   Example
    /// 0x0000000100004a1c $s7Example5crashyyF + 48"; the symbol is the image's name when `dladdr`
    /// finds no symbol, and `0x0` when it finds no image either), or MetricKit's, which have no symbol ("1 Example 0x100004000 +
    /// 16384"). The Hangs plugin reads the same lines with a type of its own: the plugins are
    /// vertical, and a dozen lines cost less than a shared module.
    struct StackFrame: Equatable {
        let index: Int
        let image: String
        /// The function, without its offset; the address and offset when the line names none.
        let symbol: String

        /// The parts of `line`; a line that isn't in either form is its own symbol, at
        /// `position`, in an unknown image.
        ///
        /// - Complexity: O(*n*), where *n* is the length of `line`.
        init(line: String, position: Int) {
            // The image is everything between the index and the first address, so a padded
            // column or an image whose name has spaces ("My App") reads whole; the symbol is
            // everything after the address, so an Objective-C method's spaces stay in it.
            guard let match = line.wholeMatch(of: #/\s*(\d+)\s+(.+?)\s+(0x[[:xdigit:]]+)(?:\s+(.*?))?\s*/#),
                  let index = Int(match.1) else {
                self.init(index: position, image: "???", symbol: line)
                return
            }
            let address = match.3
            let rest = match.4 ?? ""
            // A class method ("+[NSException raise:format:]") starts with a plus too, so only a
            // bare "+ <offset>" is MetricKit's.
            let symbol = if rest.isEmpty || rest.wholeMatch(of: #/\+\s*\d+/#) != nil {
                // MetricKit's line: the address and its offset into the image are all it has.
                rest.isEmpty ? String(address) : "\(address) \(rest)"
            } else if let offset = rest.range(of: " + ", options: .backwards) {
                String(rest[..<offset.lowerBound])
            } else {
                String(rest)
            }
            self.init(index: index, image: String(match.2), symbol: symbol)
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
