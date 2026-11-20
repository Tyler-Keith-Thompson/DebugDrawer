#if DEBUG
    import Combine
    @testable import DebugDrawerNetworkPlugin
    import Foundation

    /// A conditioning scheduler that never runs what it is given: nothing in these tests is
    /// conditioned.
    struct IdleNetworkConditionScheduler: NetworkConditionScheduler {
        func schedule(after delay: Duration, _ work: @escaping @Sendable () -> Void) -> AnyCancellable {
            AnyCancellable {}
        }
    }

    /// A die that always rolls 0.
    struct ZeroNetworkConditionRandomSource: NetworkConditionRandomSource {
        func rollPercent() -> Int { 0 }
    }

    /// A resend that goes nowhere.
    struct UnsentNetworkReplaySender: NetworkReplaySender {
        func send(_ request: URLRequest) async throws {}
    }
#endif
