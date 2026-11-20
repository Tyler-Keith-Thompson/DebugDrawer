#if DEBUG
    @testable import DebugDrawerAppStateReset

    /// A URL cache that reports the usage it is given and counts its clears.
    @MainActor
    final class FakeResponseCache: ResponseCache {
        var currentDiskUsage: Int
        var currentMemoryUsage: Int
        private(set) var removals = 0

        init(disk: Int = 0, memory: Int = 0) {
            currentDiskUsage = disk
            currentMemoryUsage = memory
        }

        func removeAllCachedResponses() {
            removals += 1
            currentDiskUsage = 0
            currentMemoryUsage = 0
        }
    }
#endif
