#if DEBUG
    import DebugDrawerNetwork
    import Foundation

    /// A profile as the editor holds it while it is changed: text for every number, checked when
    /// saved.
    struct NetworkConditionDraft: Equatable {
        let id: UUID
        /// Whether the profile isn't saved yet: Add Condition makes one.
        let isNew: Bool
        var isEnabled: Bool
        var name: String
        var hostKind: NetworkMockDraft.PatternKind
        var host: String
        /// Milliseconds.
        var latency: String
        /// Kilobytes (of 1,000 bytes) a second; empty for no cap.
        var bandwidth: String
        /// Percent.
        var failureRate: String
        var failure: NetworkConditionProfile.Failure

        /// The editor's fields for `profile`.
        ///
        /// - Parameter isNew: Whether the profile isn't saved yet.
        init(_ profile: NetworkConditionProfile, isNew: Bool) {
            id = profile.id
            self.isNew = isNew
            isEnabled = profile.isEnabled
            name = profile.name
            (hostKind, host) = NetworkMockDraft.fields(profile.host)
            latency = String(max(profile.latency.milliseconds, 0))
            bandwidth = profile.bandwidth.map(Self.kilobytesText) ?? ""
            failureRate = String(profile.failureRate)
            failure = profile.failure
        }

        /// A draft for a new profile: every host, nothing added.
        static func new() -> NetworkConditionDraft {
            NetworkConditionDraft(NetworkConditionProfile(name: ""), isNew: true)
        }

        /// Fills the latency, bandwidth and failure from `preset`, and the name, when it is empty.
        mutating func apply(_ preset: NetworkConditionPreset) {
            latency = String(preset.latency.milliseconds)
            bandwidth = preset.bandwidth.map(Self.kilobytesText) ?? ""
            failureRate = String(preset.failureRate)
            failure = preset.failure
            if name.trimmingCharacters(in: .whitespaces).isEmpty {
                name = preset.name
            }
        }

        // MARK: Checking

        /// Why the host field can't be saved, or `nil` when it can.
        var hostProblem: String? {
            NetworkMockDraft.problem(kind: hostKind, text: host, noun: "host", separator: ".", caseInsensitive: true)
        }

        /// Why the latency can't be saved, or `nil` when it can.
        var latencyProblem: String? {
            latencyMilliseconds == nil ? "Enter a latency of 0 ms or more." : nil
        }

        /// Why the bandwidth can't be saved, or `nil` when it can.
        var bandwidthProblem: String? {
            bandwidthBytes == nil ? "Enter a bandwidth above 0 KB/s, or leave it empty for no cap." : nil
        }

        /// Why the failure rate can't be saved, or `nil` when it can.
        var failureRateProblem: String? {
            failureRatePercent == nil ? "Enter a failure rate from 0 to 100%." : nil
        }

        /// The profile the fields describe, or `nil` while one of them has a problem. An empty
        /// name is the host and effect summary.
        var profile: NetworkConditionProfile? {
            guard hostProblem == nil, let latency = latencyMilliseconds, let bandwidth = bandwidthBytes,
                  let rate = failureRatePercent else { return nil }
            var profile = NetworkConditionProfile(
                id: id,
                name: name.trimmingCharacters(in: .whitespaces),
                isEnabled: isEnabled,
                host: NetworkMockDraft.pattern(hostKind, host.trimmingCharacters(in: .whitespaces)),
                latency: .milliseconds(latency),
                bandwidth: bandwidth,
                failureRate: rate,
                failure: failure
            )
            if profile.name.isEmpty {
                profile.name = "\(profile.hostSummary.capitalizedFirst) \(profile.effectSummary)"
            }
            return profile
        }

        // MARK: Converting

        private var latencyMilliseconds: Int64? {
            Int64(latency.trimmingCharacters(in: .whitespaces)).flatMap { $0 >= 0 ? $0 : nil }
        }

        /// The cap in bytes a second: `.some(nil)` for an empty field, `nil` for one that isn't a
        /// positive number.
        private var bandwidthBytes: Int?? {
            let text = bandwidth.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { return .some(nil) }
            // Bounded first, so the conversion to Int below can't trap.
            guard let kilobytes = Double(text), kilobytes > 0, kilobytes < 1_000_000_000 else { return nil }
            let bytes = Int((kilobytes * 1000).rounded())
            return bytes >= 1 ? .some(bytes) : nil
        }

        private var failureRatePercent: Int? {
            Int(failureRate.trimmingCharacters(in: .whitespaces)).flatMap { (0 ... 100).contains($0) ? $0 : nil }
        }

        /// Bytes a second in kilobytes, without a needless decimal: "97.5", "30".
        private static func kilobytesText(_ bytes: Int) -> String {
            bytes % 1000 == 0 ? String(bytes / 1000) : String(Double(bytes) / 1000)
        }
    }

    extension String {
        /// The text with its first letter capitalized: "all hosts" reads "All hosts".
        fileprivate var capitalizedFirst: String {
            prefix(1).uppercased() + dropFirst()
        }
    }
#endif
