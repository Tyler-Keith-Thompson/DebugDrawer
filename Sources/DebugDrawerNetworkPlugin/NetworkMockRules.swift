#if DEBUG
    import DebugDrawerNetwork
    import Foundation
    import os

    /// The rules the URL protocol answers from: the enabled ones that compile, in order, each with
    /// its response ready to send.
    ///
    /// The URL loading system asks from its own threads and the drawer changes the rules on the
    /// main actor, so the rules sit behind a lock rather than in an actor, which would make each
    /// request wait for a hop. `OSAllocatedUnfairLock` rather than `Mutex`, which needs iOS 18;
    /// switch to `Mutex` once iOS 18 is the minimum.
    final class NetworkMockRules: Sendable {
        /// The rules `DebugNetworkProtocol` answers from. Empty until `installNetwork()` loads the
        /// saved ones.
        static let shared = NetworkMockRules()

        fileprivate struct ActiveRule: Sendable {
            let matcher: CompiledNetworkMockMatcher
            let answer: NetworkMockAnswer
        }

        private let active = OSAllocatedUnfairLock<[ActiveRule]>(initialState: [])

        /// Answers from `rules` from now on: the enabled ones, in order, less any whose pattern
        /// doesn't compile.
        ///
        /// - Parameters:
        ///   - rules: The rules, the first to match answering.
        ///   - body: The contents of a body file, by name; `nil` sends an empty body.
        func activate(_ rules: [NetworkMockRule], body: (String) -> Data?) {
            let compiled = rules.filter(\.isEnabled).compactMap { rule -> ActiveRule? in
                guard let matcher = try? CompiledNetworkMockMatcher(rule.matcher) else { return nil }
                return ActiveRule(matcher: matcher, answer: rule.answer(body: body))
            }
            active.withLock { $0 = compiled }
        }

        /// The answer of the first active rule that matches a request of `method` to `url`, or
        /// `nil` when none does.
        ///
        /// - Complexity: O(*n*) in the number of active rules.
        func answer(method: String, url: URL) -> NetworkMockAnswer? {
            active.withLock { rules in
                guard !rules.isEmpty else { return nil }
                let request = CompiledNetworkMockMatcher.Request(method: method, url: url)
                return rules.first { $0.matcher.matches(request) }?.answer
            }
        }
    }
#endif
