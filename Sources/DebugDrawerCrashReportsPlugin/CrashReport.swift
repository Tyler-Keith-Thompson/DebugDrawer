#if DEBUG
    import Foundation

    /// One crash: what ended the app, when, which version it was, and the stack it was on.
    struct CrashReport: Codable, Equatable, Identifiable, Sendable {
        /// Where a report came from.
        enum Source: String, Codable, Sendable {
            /// Written by the plugin's own handlers as the app crashed.
            case captured
            /// An `MXCrashDiagnostic` MetricKit delivered.
            case metricKit
        }

        let id: UUID
        /// When the app crashed.
        let date: Date
        /// The signal's name (`SIGSEGV`) or the exception's (`NSInvalidArgumentException`).
        let title: String
        /// What the signal means, the exception's reason or MetricKit's termination reason.
        let reason: String?
        /// The version and build of the app that crashed (`1.2 (34)`).
        let appVersion: String?
        /// The crashed thread's frames, innermost first, one line each.
        let frames: [String]
        let source: Source
        /// Whether the developer has opened the report in the drawer.
        var isSeen: Bool
    }

    extension CrashReport {
        /// The report as text: a header of what, when and which version, then the frames.
        func text(dateFormat: Date.ISO8601FormatStyle = .iso8601) -> String {
            let header = [
                reason.map { "\(title): \($0)" } ?? title,
                "Date: \(date.formatted(dateFormat))",
                appVersion.map { "App: \($0)" },
                "Source: \(source.title)"
            ]
            let frameLines = frames.isEmpty ? ["No stack trace was recorded."] : frames
            return (header.compactMap(\.self) + [""] + frameLines).joined(separator: "\n") + "\n"
        }
    }

    extension CrashReport.Source {
        /// How the drawer names it.
        var title: String {
            switch self {
            case .captured: "Captured"
            case .metricKit: "MetricKit"
            }
        }
    }
#endif
