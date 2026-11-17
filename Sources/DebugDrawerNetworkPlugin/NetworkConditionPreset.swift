#if DEBUG
    /// A profile's effect, ready-made, that the editor fills its fields from.
    ///
    /// The figures follow the Network Link Conditioner's profiles of the same names: their
    /// downlink bandwidth and delay, with "Very Bad Network"'s packet loss as a share of requests
    /// that time out, since a request here fails whole or not at all.
    struct NetworkConditionPreset: Identifiable, Equatable {
        let name: String
        let latency: Duration
        /// Bytes a second.
        let bandwidth: Int?
        let failureRate: Int
        let failure: NetworkConditionProfile.Failure

        var id: String {
            name
        }

        /// The presets the editor offers, slowest last.
        static let all = [
            NetworkConditionPreset(name: "3G", latency: .milliseconds(100), bandwidth: 97500, failureRate: 0, failure: .timedOut),
            NetworkConditionPreset(name: "Edge", latency: .milliseconds(400), bandwidth: 30000, failureRate: 0, failure: .timedOut),
            NetworkConditionPreset(name: "Lossy", latency: .milliseconds(500), bandwidth: 125_000, failureRate: 10, failure: .timedOut)
        ]
    }
#endif
