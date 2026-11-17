#if DEBUG
    @testable import DebugDrawerNetworkPlugin
    import Foundation
    import os

    /// The profiles file in memory. Setting `failsWriting` makes every write throw, as a full disk
    /// would.
    final class FakeNetworkConditionStorage: NetworkConditionStorage {
        struct WriteFailed: Error {}

        private struct State {
            var profiles: Data?
            var failsWriting = false
        }

        private let state: OSAllocatedUnfairLock<State>

        init(profiles: Data? = nil) {
            state = OSAllocatedUnfairLock(initialState: State(profiles: profiles))
        }

        var savedProfiles: Data? {
            state.withLock(\.profiles)
        }

        var failsWriting: Bool {
            get { state.withLock(\.failsWriting) }
            set { state.withLock { $0.failsWriting = newValue } }
        }

        func readProfiles() throws -> Data? {
            state.withLock(\.profiles)
        }

        func writeProfiles(_ data: Data) throws {
            try state.withLock { state in
                guard !state.failsWriting else { throw WriteFailed() }
                state.profiles = data
            }
        }
    }
#endif
