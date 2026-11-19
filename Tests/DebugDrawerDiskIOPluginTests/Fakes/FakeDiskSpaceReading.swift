#if DEBUG
    @testable import DebugDrawerDiskIOPlugin
    import Foundation

    /// Hands out the volumes it is given, in order, reading no file system. While it holds, each
    /// read waits until the test releases it.
    @MainActor
    final class FakeDiskSpaceReading: DiskSpaceReading {
        /// What each read returns, first to last.
        private var results: [DiskSpace?]
        /// How many reads were asked for.
        private(set) var reads = 0
        private var holds: Bool
        private var waiting: [CheckedContinuation<Void, Never>] = []

        /// - Parameters:
        ///   - results: What each read returns, first to last.
        ///   - holds: Whether a read waits for ``release()`` before it returns.
        init(_ results: [DiskSpace?], holds: Bool = false) {
            self.results = results
            self.holds = holds
        }

        func read() async -> DiskSpace? {
            reads += 1
            if holds {
                await withCheckedContinuation { waiting.append($0) }
            }
            return results.removeFirst()
        }

        /// Lets the reads held, and every later one, return.
        func release() {
            holds = false
            for read in waiting {
                read.resume()
            }
            waiting = []
        }
    }
#endif
