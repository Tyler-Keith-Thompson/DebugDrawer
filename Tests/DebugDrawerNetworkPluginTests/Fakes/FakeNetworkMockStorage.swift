#if DEBUG
    import Foundation
    import os
    @testable import DebugDrawerNetworkPlugin

    /// The rules file and body files in memory. Setting `failsWriting` makes every write throw, as a
    /// full disk would.
    final class FakeNetworkMockStorage: NetworkMockStorage {
        struct WriteFailed: Error {}

        private struct State {
            var rules: Data?
            var bodies: [String: Data] = [:]
            var failsWriting = false
            var nextBody = 1
        }

        private let state: OSAllocatedUnfairLock<State>

        init(rules: Data? = nil, bodies: [String: Data] = [:]) {
            state = OSAllocatedUnfairLock(initialState: State(rules: rules, bodies: bodies))
        }

        var savedRules: Data? {
            state.withLock(\.rules)
        }

        var bodies: [String: Data] {
            state.withLock(\.bodies)
        }

        var failsWriting: Bool {
            get { state.withLock(\.failsWriting) }
            set { state.withLock { $0.failsWriting = newValue } }
        }

        func readRules() throws -> Data? {
            state.withLock(\.rules)
        }

        func writeRules(_ data: Data) throws {
            try state.withLock { state in
                guard !state.failsWriting else { throw WriteFailed() }
                state.rules = data
            }
        }

        func addBody(_ data: Data, fileExtension: String?) throws -> String {
            try state.withLock { state in
                guard !state.failsWriting else { throw WriteFailed() }
                let name = "body-\(state.nextBody)" + (fileExtension.map { "." + $0 } ?? "")
                state.nextBody += 1
                state.bodies[name] = data
                return name
            }
        }

        func writeBody(_ data: Data, named name: String) throws {
            try state.withLock { state in
                guard !state.failsWriting else { throw WriteFailed() }
                state.bodies[name] = data
            }
        }

        func body(named name: String) -> Data? {
            state.withLock { $0.bodies[name] }
        }

        func removeBody(named name: String) {
            _ = state.withLock { $0.bodies.removeValue(forKey: name) }
        }
    }
#endif
