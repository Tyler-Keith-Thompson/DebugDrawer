#if DEBUG
    import Foundation

    extension NetworkConditionProfile {
        /// The hosts the profile applies to, as one line: `api.example.com`, a regex after
        /// "regex", or "all hosts".
        var hostSummary: String {
            host.summary(any: "all hosts")
        }

        /// What the profile does, as one line: "2,000 ms · 97.5 KB/s · 10% timeout", each part only
        /// when the profile does it, or "No effect".
        var effectSummary: String {
            var parts: [String] = []
            if latency > .zero {
                parts.append(latency.millisecondsText)
            }
            if let bandwidth, bandwidth > 0 {
                parts.append(bandwidth.bandwidthText)
            }
            if failureRate > 0 {
                parts.append("\(min(failureRate, 100))% \(failure.phrase)")
            }
            return parts.isEmpty ? "No effect" : parts.joined(separator: " · ")
        }

        /// Whether the profile's host pattern doesn't compile, so the profile never applies.
        var hasInvalidHost: Bool {
            (try? CompiledPattern(host, separator: ".", caseInsensitive: true)) == nil
        }
    }

    extension [NetworkConditionProfile] {
        /// The header's short form of ``activeSummary``: "1 active", "2 active"; `nil` while none
        /// is on. It leaves out the name, whose length has no bound, so the header keeps its row.
        var activeCountLabel: String? {
            let count = count(where: \.isEnabled)
            return count == 0 ? nil : "\(count.formatted()) active"
        }

        /// What the indicator says while profiles are on: "3G active" for one, "2 conditions
        /// active" for more; `nil` while none is.
        var activeSummary: String? {
            let enabled = filter(\.isEnabled)
            switch enabled.count {
            case 0: return nil
            case 1: return "\(enabled[0].name) active"
            default: return "\(enabled.count.formatted()) conditions active"
            }
        }
    }
#endif
