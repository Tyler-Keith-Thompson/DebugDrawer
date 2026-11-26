#if DEBUG
    import Foundation

    /// Turns the bytes a stream delivers, in reads cut wherever the pipe happened to cut them, into
    /// whole lines of text.
    ///
    /// A read can end inside a line, and inside a multi-byte UTF-8 character, so the bytes after
    /// the last newline wait for the next read. A line is decoded only once its newline arrives,
    /// and a newline byte is never part of a multi-byte sequence, so every character in it is
    /// whole. Bytes that aren't UTF-8 decode as U+FFFD rather than losing the line. A line ending
    /// in a carriage return and a newline loses the carriage return.
    struct ConsoleLineAssembler {
        /// The most bytes a line waits for its newline with; a longer one is cut there, at the
        /// start of the UTF-8 sequence it would split, and the rest starts the next line.
        let maximumLineLength: Int
        /// The bytes after the last newline, waiting for the next read.
        private var remainder = Data()

        /// An assembler holding no bytes.
        ///
        /// - Parameter maximumLineLength: The most bytes a line waits for its newline with; at
        ///   least 4, the longest UTF-8 sequence.
        init(maximumLineLength: Int = 16384) {
            // Can't fire: the type is internal, and the module makes it only with the default; no
            // input reaches it.
            precondition(maximumLineLength >= 4, "A line must hold the longest UTF-8 sequence")
            self.maximumLineLength = maximumLineLength
        }

        /// The lines `chunk` completes, oldest first, each without its newline; the bytes after
        /// its last newline wait for the next read.
        ///
        /// - Complexity: O(*n*) in the bytes of `chunk` and those waiting before it.
        mutating func lines(in chunk: Data) -> [String] {
            var completed: [String] = []
            var start = chunk.startIndex
            while let end = chunk[start...].firstIndex(of: .newline) {
                if remainder.isEmpty {
                    completed.append(Self.line(from: chunk[start ..< end]))
                } else {
                    remainder.append(chunk[start ..< end])
                    completed.append(Self.line(from: remainder))
                    remainder.removeAll(keepingCapacity: true)
                }
                start = chunk.index(after: end)
            }
            remainder.append(chunk[start...])
            while remainder.count > maximumLineLength {
                let cut = remainder.utf8Boundary(atOrBefore: remainder.startIndex + maximumLineLength)
                completed.append(Self.text(of: remainder[..<cut]))
                remainder = Data(remainder[cut...])
            }
            return completed
        }

        /// The line the stream ended in without a newline, if any; the assembler then holds no
        /// bytes.
        ///
        /// A stream that ends shows what it printed last, so a final line with no newline is a
        /// line rather than being dropped.
        mutating func flush() -> String? {
            guard !remainder.isEmpty else { return nil }
            defer { remainder.removeAll() }
            return Self.line(from: remainder)
        }

        /// The text of `bytes`, a line without its newline, less a trailing carriage return.
        private static func line(from bytes: Data) -> String {
            text(of: bytes.last == .carriageReturn ? bytes.dropLast() : bytes[...])
        }

        /// `bytes` decoded as UTF-8, each sequence that isn't UTF-8 replaced by U+FFFD.
        ///
        /// A console shows what was printed, so a line with a stray byte shows with a
        /// replacement character in place of that byte rather than not at all. Valid text, the
        /// usual case, takes the validating initializer; only text that fails it is decoded
        /// scalar by scalar.
        private static func text(of bytes: Data) -> String {
            if let text = String(bytes: bytes, encoding: .utf8) { return text }
            var codec = UTF8()
            var iterator = bytes.makeIterator()
            var scalars = String.UnicodeScalarView()
            while true {
                switch codec.decode(&iterator) {
                case let .scalarValue(scalar): scalars.append(scalar)
                case .error: scalars.append("\u{FFFD}")
                case .emptyInput: return String(scalars)
                }
            }
        }
    }

    extension UInt8 {
        fileprivate static let newline = UInt8(ascii: "\n")
        fileprivate static let carriageReturn = UInt8(ascii: "\r")

        /// Whether the byte continues a multi-byte UTF-8 sequence (`10xxxxxx`) rather than
        /// starting one.
        fileprivate var isUTF8Continuation: Bool {
            self & 0b1100_0000 == 0b1000_0000
        }
    }

    extension Data {
        /// The latest index at or before `index` that doesn't split a UTF-8 sequence; `index`
        /// itself when the bytes before it are all continuation bytes, which no valid text has.
        fileprivate func utf8Boundary(atOrBefore index: Index) -> Index {
            // A sequence is at most 4 bytes, so its start is at most 3 back.
            let earliest = Swift.max(startIndex, index - 3)
            return self[earliest ... index].lastIndex { !$0.isUTF8Continuation } ?? index
        }
    }
#endif
