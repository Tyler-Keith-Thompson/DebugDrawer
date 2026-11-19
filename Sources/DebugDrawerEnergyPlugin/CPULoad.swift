#if DEBUG
    // The process's CPU use, bucketed. It is not Xcode's Energy Impact: that also weighs GPU,
    // network, location and wakeups, which aren't measured here.

    /// How heavy this process's CPU use is: under 5% low, under 20% moderate, under 50% high, and
    /// very high from there.
    enum CPULoad: String, Codable, Equatable, Sendable, CaseIterable {
        case low
        case moderate
        case high
        case veryHigh

        /// - Parameter cpuUsage: The process's CPU use, in percent of one core.
        init(cpuUsage: Double) {
            if cpuUsage < 5 {
                self = .low
            } else if cpuUsage < 20 {
                self = .moderate
            } else if cpuUsage < 50 {
                self = .high
            } else {
                self = .veryHigh
            }
        }
    }
#endif
