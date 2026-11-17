#if DEBUG
    @testable import DebugDrawerDeepLinkPlugin
    import Foundation

    /// A continuation path that keeps every activity it's handed and answers as it's told.
    @MainActor
    final class FakeUserActivityDelivering: UserActivityDelivering {
        /// Where every activity is said to go.
        var answer: UserActivityDelivery
        private(set) var delivered: [NSUserActivity] = []

        init(answer: UserActivityDelivery = .handler) {
            self.answer = answer
        }

        func deliver(_ activity: NSUserActivity) -> UserActivityDelivery {
            delivered.append(activity)
            return answer
        }
    }
#endif
