#if DEBUG
    @testable import DebugDrawerNetworkPlugin
    import Foundation
    import os

    /// Keeps every request it is asked to send, and sends none. With `failure` set, each send
    /// throws it. Made gated, each send waits until the test calls `open()`; `waitUntilSent(_:)`
    /// returns once that many sends have started.
    final class FakeNetworkReplaySender: NetworkReplaySender {
        private struct State {
            var sent: [URLRequest] = []
            var isOpen: Bool
            var gate: [CheckedContinuation<Void, Never>] = []
            var sentWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
        }

        private let failure: (any Error & Sendable)?
        private let state: OSAllocatedUnfairLock<State>

        init(failure: (any Error & Sendable)? = nil, gated: Bool = false) {
            self.failure = failure
            state = OSAllocatedUnfairLock(initialState: State(isOpen: !gated))
        }

        /// The requests asked for, in order.
        var sent: [URLRequest] {
            state.withLock(\.sent)
        }

        func send(_ request: URLRequest) async throws {
            let ready = state.withLock { state in
                state.sent.append(request)
                let count = state.sent.count
                let ready = state.sentWaiters.filter { $0.count <= count }.map(\.continuation)
                state.sentWaiters.removeAll { $0.count <= count }
                return ready
            }
            ready.forEach { $0.resume() }
            await withCheckedContinuation { continuation in
                let isOpen = state.withLock { state in
                    if !state.isOpen { state.gate.append(continuation) }
                    return state.isOpen
                }
                if isOpen { continuation.resume() }
            }
            if let failure { throw failure }
        }

        /// Lets every waiting send, and every later one, finish.
        func open() {
            let waiting = state.withLock { state in
                state.isOpen = true
                defer { state.gate = [] }
                return state.gate
            }
            waiting.forEach { $0.resume() }
        }

        /// Returns once `count` sends have started.
        func waitUntilSent(_ count: Int) async {
            await withCheckedContinuation { continuation in
                let isMet = state.withLock { state in
                    guard state.sent.count < count else { return true }
                    state.sentWaiters.append((count, continuation))
                    return false
                }
                if isMet { continuation.resume() }
            }
        }
    }
#endif
