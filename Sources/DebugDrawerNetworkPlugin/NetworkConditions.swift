#if DEBUG
    import DebugDrawerNetwork
    import Foundation
    import os

    /// The profiles the URL protocol conditions requests by: the enabled ones that compile, in
    /// order, with the scheduler that times their latency and bandwidth and the random source that
    /// decides their failures.
    ///
    /// The URL loading system asks from its own threads and the drawer changes the profiles on the
    /// main actor, so they sit behind a lock rather than in an actor, as the mock rules do.
    /// `OSAllocatedUnfairLock` rather than `Mutex`, which needs iOS 18; switch to `Mutex` once iOS
    /// 18 is the minimum.
    final class NetworkConditions: Sendable {
        /// The profiles `DebugNetworkProtocol` conditions requests by. Empty until
        /// `installNetwork()` loads the saved ones.
        static let shared = NetworkConditions()

        fileprivate struct ActiveProfile: Sendable {
            let host: CompiledPattern
            let profile: NetworkConditionProfile
        }

        private struct State: Sendable {
            var profiles: [ActiveProfile] = []
            var scheduler: any NetworkConditionScheduler = _NetworkConditionScheduler()
            var random: any NetworkConditionRandomSource = _NetworkConditionRandomSource()
        }

        private let state = OSAllocatedUnfairLock(initialState: State())

        /// Conditions requests by `profiles` from now on: the enabled ones, in order, less any whose
        /// host pattern doesn't compile.
        ///
        /// - Parameters:
        ///   - profiles: The profiles, the first to match applying.
        ///   - scheduler: What times the latency and the bandwidth cap.
        ///   - random: What decides which requests fail.
        func activate(
            _ profiles: [NetworkConditionProfile],
            scheduler: any NetworkConditionScheduler,
            random: any NetworkConditionRandomSource
        ) {
            let compiled = profiles.filter(\.isEnabled).compactMap { profile -> ActiveProfile? in
                guard let host = try? CompiledPattern(profile.host, separator: ".", caseInsensitive: true) else { return nil }
                return ActiveProfile(host: host, profile: profile)
            }
            state.withLock { $0 = State(profiles: compiled, scheduler: scheduler, random: random) }
        }

        /// How the first active profile whose host matches `url`'s conditions a request to it, with
        /// its failure decided now; `nil` when none matches, and the request is left alone.
        ///
        /// - Complexity: O(*n*) in the number of active profiles.
        func plan(for url: URL) -> NetworkConditionPlan? {
            let host = url.host() ?? ""
            let (match, scheduler, random) = state.withLock { state in
                (state.profiles.first { $0.host.matches(host) }?.profile, state.scheduler, state.random)
            }
            guard let match else { return nil }
            return NetworkConditionPlan(effect: match.effect(failing: random), scheduler: scheduler)
        }
    }
#endif
