#if DEBUG
    @testable import DebugDrawerConsolePlugin
    import Foundation
    import os

    /// Sessions in memory. Setting `failsReading` makes every read throw, as a file gone
    /// unreadable would; setting `holdsAppends` makes each append from then on wait until the
    /// test calls `releaseAppend()`, after announcing itself on `appendsStarted`.
    final class FakeConsoleSessionStorage: ConsoleSessionStorage {
        struct ReadFailed: Error {}

        private struct State {
            var sessions: [String: Data] = [:]
            var failsReading = false
            var holdsAppends = false
        }

        private let state: OSAllocatedUnfairLock<State>
        private let gate = DispatchSemaphore(value: 0)
        private let started: AsyncStream<Void>.Continuation
        /// Yields once as each append begins, before it waits on the gate.
        let appendsStarted: AsyncStream<Void>

        init(sessions: [String: Data] = [:]) {
            state = OSAllocatedUnfairLock(initialState: State(sessions: sessions))
            (appendsStarted, started) = AsyncStream.makeStream()
        }

        var sessions: [String: Data] {
            state.withLock(\.sessions)
        }

        var failsReading: Bool {
            get { state.withLock(\.failsReading) }
            set { state.withLock { $0.failsReading = newValue } }
        }

        var holdsAppends: Bool {
            get { state.withLock(\.holdsAppends) }
            set { state.withLock { $0.holdsAppends = newValue } }
        }

        /// Lets one held append go on.
        func releaseAppend() {
            gate.signal()
        }

        func sessionFiles() throws -> [ConsoleSessionFile] {
            state.withLock { $0.sessions.map { ConsoleSessionFile(name: $0.key, byteCount: $0.value.count) } }
        }

        func append(_ data: Data, toSessionNamed name: String) throws {
            if holdsAppends {
                started.yield()
                gate.wait()
            }
            state.withLock { $0.sessions[name, default: Data()].append(data) }
        }

        func contents(ofSessionNamed name: String) throws -> Data {
            try state.withLock { state in
                guard !state.failsReading, let data = state.sessions[name] else { throw ReadFailed() }
                return data
            }
        }

        func deleteSession(named name: String) throws {
            _ = state.withLock { $0.sessions.removeValue(forKey: name) }
        }
    }
#endif
