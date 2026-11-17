#if DEBUG
    @testable import DebugDrawerConsolePlugin
    import Foundation
    import os

    /// The mutes' file in memory. Setting `failsWriting` makes every write throw, as a full disk
    /// would.
    final class FakeConsoleMuteStorage: ConsoleMuteStorage {
        struct WriteFailed: Error {}

        private struct State {
            var data: Data?
            var failsWriting = false
        }

        private let state: OSAllocatedUnfairLock<State>

        init(data: Data? = nil) {
            state = OSAllocatedUnfairLock(initialState: State(data: data))
        }

        /// What was last written, or the file it started with.
        var data: Data? {
            state.withLock(\.data)
        }

        var failsWriting: Bool {
            get { state.withLock(\.failsWriting) }
            set { state.withLock { $0.failsWriting = newValue } }
        }

        func readMutes() throws -> Data? {
            state.withLock(\.data)
        }

        func writeMutes(_ data: Data) throws {
            try state.withLock { state in
                guard !state.failsWriting else { throw WriteFailed() }
                state.data = data
            }
        }
    }
#endif
