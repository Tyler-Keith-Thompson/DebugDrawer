#if DEBUG
    import DebugDrawerNetwork
    import os

    /// Rolls the percents it is given, in turn, then the last again.
    struct FixedNetworkConditionRandomSource: NetworkConditionRandomSource {
        private let rolls: OSAllocatedUnfairLock<[Int]>

        init(_ rolls: Int...) {
            self.rolls = OSAllocatedUnfairLock(initialState: rolls)
        }

        func rollPercent() -> Int {
            rolls.withLock { rolls in
                rolls.count > 1 ? rolls.removeFirst() : rolls.first ?? 0
            }
        }
    }
#endif
