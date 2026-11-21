#if DEBUG && canImport(DebugDrawerConsolePlugin)
    @testable import DebugDrawerConsolePlugin
    import Foundation
    import os

    /// The Console's saved mutes in memory.
    final class InMemoryConsoleMuteStorage: ConsoleMuteStorage {
        private let file = OSAllocatedUnfairLock<Data?>(initialState: nil)

        func readMutes() throws -> Data? { file.withLock { $0 } }
        func writeMutes(_ data: Data) throws { file.withLock { $0 = data } }
    }
#endif
