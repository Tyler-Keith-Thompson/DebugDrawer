#if DEBUG
    /// Decides which requests a profile fails: a profile fails a request when the roll is below
    /// its failure rate. Tests replace it with rolls they choose.
    protocol NetworkConditionRandomSource: Sendable {
        /// A whole percent from 0 through 99, each equally likely.
        func rollPercent() -> Int
    }

    /// Rolls with the system's generator.
    struct _NetworkConditionRandomSource: NetworkConditionRandomSource {
        func rollPercent() -> Int {
            var generator = SystemRandomNumberGenerator()
            return Int.random(in: 0 ..< 100, using: &generator)
        }
    }
#endif
