#if DEBUG
    import Foundation
    import os

    /// A response body as the log captures it while it arrives: its first `limit` bytes, and a
    /// count of every byte, so a download or a stream that never ends costs the log at most
    /// `limit` bytes.
    struct NetworkBodyCapture {
        /// The most bytes of a body the log keeps, from `installNetwork(bodyLimit:)`; read by each
        /// request as it starts. Behind a lock, as requests start on URLSession's threads.
        static let limit = OSAllocatedUnfairLock(initialState: defaultLimit)

        /// The limit until `installNetwork(bodyLimit:)` sets one: 1 MiB.
        static let defaultLimit = 1_048_576

        /// The most bytes kept.
        let limit: Int
        /// The bytes kept so far: the body's first bytes, at most `limit` of them.
        private(set) var data = Data()
        /// How many bytes have arrived, kept or not.
        private(set) var size = 0

        /// An empty capture that keeps at most `limit` bytes.
        ///
        /// - Parameter limit: The most bytes kept; 0 or more.
        init(limit: Int) {
            // Can't fire: the type is internal, and every limit it is given is the process's
            // `NetworkBodyCapture.limit`, which is the non-negative default or a body limit
            // installNetwork took after throwing on a negative one, or that limit passed on.
            precondition(limit >= 0, "A body limit can't be negative")
            self.limit = limit
        }

        /// Counts `chunk`, and keeps as much of it as fits under the limit.
        ///
        /// - Complexity: O(*n*) in the bytes kept from `chunk`.
        mutating func append(_ chunk: Data) {
            size += chunk.count
            let room = limit - data.count
            guard room > 0 else { return }
            data.append(chunk.prefix(room))
        }

        /// The body as the log keeps it, with its full size. A body cut short loses the last
        /// character the limit split in two, if any, so a text body that was cut still reads as
        /// UTF-8 text.
        var body: NetworkResponseBody {
            NetworkResponseBody(keptData, size: size)
        }

        /// The bytes the log keeps: all of them, or, for a body cut short, the bytes kept without
        /// the last character the limit split in two, as `body` keeps them.
        var keptData: Data {
            size > data.count ? data.droppingSplitUTF8Character : data
        }
    }

    extension Data {
        /// These bytes without a UTF-8 character's leading bytes at the end, whose remaining bytes
        /// are missing. Any other bytes, binary ones included, are kept.
        fileprivate var droppingSplitUTF8Character: Data {
            // Looks back past at most three continuation bytes (10xxxxxx) to the byte that leads
            // their character, whose high bits say how many bytes the character has.
            var continuationCount = 0
            for index in indices.reversed().prefix(4) {
                let byte = self[index]
                if byte & 0b1100_0000 == 0b1000_0000 {
                    continuationCount += 1
                    continue
                }
                let length = byte >= 0b1111_0000 ? 4 : byte >= 0b1110_0000 ? 3 : byte >= 0b1100_0000 ? 2 : 1
                return length > continuationCount + 1 ? Data(self[startIndex ..< index]) : self
            }
            return self
        }
    }
#endif
