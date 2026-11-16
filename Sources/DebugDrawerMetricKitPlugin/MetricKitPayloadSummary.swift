#if DEBUG
    import Foundation

    /// What a payload holds, read from its JSON: for metrics, the app's version and how many
    /// groups of metrics it reports; for diagnostics, how many of each kind.
    enum MetricKitPayloadSummary: Equatable {
        /// A metric payload of the app version named, reporting `sections` groups of metrics
        /// (`applicationLaunchMetrics`, `diskIOMetrics`, …).
        case metrics(appVersion: String?, sections: Int)
        /// A diagnostic payload with these counts.
        case diagnostics(DiagnosticCounts)
        /// JSON that isn't an object.
        case unreadable

        /// The counts of a diagnostic payload, by the key MetricKit lists them under.
        struct DiagnosticCounts: Equatable {
            var crashes = 0
            var hangs = 0
            var cpuExceptions = 0
            var diskWriteExceptions = 0
            var slowLaunches = 0
        }

        /// The summary of `json`, a payload of `kind`.
        init(kind: MetricKitPayloadKind, json: Data) {
            guard let object = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any] else {
                self = .unreadable
                return
            }
            switch kind {
            case .metrics:
                let version = object["appVersion"] as? String
                let build = (object["metaData"] as? [String: Any])?["appBuildVersion"] as? String
                let sections = object.count { key, value in key.hasSuffix("Metrics") && !(value is NSNull) }
                self = .metrics(appVersion: Self.version(version, build: build), sections: sections)
            case .diagnostics:
                func count(_ key: String) -> Int {
                    (object[key] as? [Any])?.count ?? 0
                }
                self = .diagnostics(DiagnosticCounts(
                    crashes: count("crashDiagnostics"),
                    hangs: count("hangDiagnostics"),
                    cpuExceptions: count("cpuExceptionDiagnostics"),
                    diskWriteExceptions: count("diskWriteExceptionDiagnostics"),
                    slowLaunches: count("appLaunchDiagnostics")
                ))
            }
        }

        /// The summary in a line: `App 1.2 (34) · 9 metric groups`, `1 crash · 2 hangs`.
        var text: String {
            switch self {
            case let .metrics(version, sections):
                let groups = sections == 1 ? "1 metric group" : "\(sections) metric groups"
                return ([version.map { "App \($0)" }, groups].compactMap(\.self)).joined(separator: " · ")
            case let .diagnostics(counts):
                let parts = [
                    Self.counted(counts.crashes, "crash", "crashes"),
                    Self.counted(counts.hangs, "hang", "hangs"),
                    Self.counted(counts.cpuExceptions, "CPU exception", "CPU exceptions"),
                    Self.counted(counts.diskWriteExceptions, "disk-write exception", "disk-write exceptions"),
                    Self.counted(counts.slowLaunches, "slow launch", "slow launches")
                ].compactMap(\.self)
                return parts.isEmpty ? "No diagnostics" : parts.joined(separator: " · ")
            case .unreadable:
                return "Not a MetricKit payload"
            }
        }
    }

    extension MetricKitPayloadSummary {
        /// `1.2 (34)`, the version or the build alone, or `nil` when the payload names neither.
        fileprivate static func version(_ version: String?, build: String?) -> String? {
            switch (version, build) {
            case let (version?, build?): "\(version) (\(build))"
            case let (version?, nil): version
            case let (nil, build?): "(\(build))"
            case (nil, nil): nil
            }
        }

        /// `count` with its noun, or `nil` for none.
        fileprivate static func counted(_ count: Int, _ singular: String, _ plural: String) -> String? {
            switch count {
            case 0: nil
            case 1: "1 \(singular)"
            default: "\(count) \(plural)"
            }
        }
    }
#endif
