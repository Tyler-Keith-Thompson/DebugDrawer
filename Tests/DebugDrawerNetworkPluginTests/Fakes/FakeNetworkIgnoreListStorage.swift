#if DEBUG
    @testable import DebugDrawerNetworkPlugin
    import Foundation
    import os

    /// The ignore list's file in memory. Setting `failsWriting` makes every write throw, as a full
    /// disk would.
    final class FakeNetworkIgnoreListStorage: NetworkIgnoreListStorage {
        struct WriteFailed: Error {}

        private struct State {
            var file: Data?
            var failsWriting = false
            var writeCount = 0
        }

        private let state: OSAllocatedUnfairLock<State>

        init(file: Data? = nil) {
            state = OSAllocatedUnfairLock(initialState: State(file: file))
        }

        var savedFile: Data? {
            state.withLock(\.file)
        }

        /// How many times the file was written.
        var writeCount: Int {
            state.withLock(\.writeCount)
        }

        var failsWriting: Bool {
            get { state.withLock(\.failsWriting) }
            set { state.withLock { $0.failsWriting = newValue } }
        }

        func readIgnoreList() throws -> Data? {
            state.withLock(\.file)
        }

        func writeIgnoreList(_ data: Data) throws {
            try state.withLock { state in
                guard !state.failsWriting else { throw WriteFailed() }
                state.file = data
                state.writeCount += 1
            }
        }
    }
#endif
