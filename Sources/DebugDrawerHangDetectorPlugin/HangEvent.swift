#if DEBUG
    import Foundation

    /// One hang of the main thread: when it began, how long it lasted, and the stack it was stuck on.
    struct HangEvent: Equatable, Identifiable, Sendable {
        /// Where a hang came from.
        enum Source: Equatable, Sendable {
            /// Caught by the plugin's own watcher as it happened.
            case detected
            /// An `MXHangDiagnostic` MetricKit delivered.
            case metricKit
        }

        let id: UUID
        /// When the hang began; for MetricKit's, the end of the period its payload covers.
        let date: Date
        let duration: Duration
        /// The main thread's frames, innermost first, one line each; empty when the thread got
        /// going before the watcher looked.
        let frames: [String]
        let source: Source
        /// Whether the developer has opened the hang in the drawer.
        var isSeen: Bool
    }

    extension HangEvent {
        /// The duration in whole milliseconds, as the drawer and the toast name it: `612 ms`.
        var durationText: String {
            Self.milliseconds(duration)
        }

        /// `duration` in whole milliseconds: `612 ms`.
        static func milliseconds(_ duration: Duration) -> String {
            let (seconds, attoseconds) = duration.components
            return "\(seconds * 1000 + attoseconds / 1_000_000_000_000_000) ms"
        }

        /// The hang as text: a header of how long, when and where from, then the frames.
        func text(dateFormat: Date.ISO8601FormatStyle = .iso8601) -> String {
            let header = [
                "Main thread hung for \(durationText)",
                "Date: \(date.formatted(dateFormat))",
                "Source: \(source.title)"
            ]
            let frameLines = frames.isEmpty ? [Self.noStack] : frames
            return (header + [""] + frameLines).joined(separator: "\n") + "\n"
        }

        /// What stands in for the frames of a hang whose stack wasn't captured.
        static let noStack = "No stack was captured: the main thread got going before the watcher looked."
    }

    extension HangEvent.Source {
        /// How the drawer names it.
        var title: String {
            switch self {
            case .detected: "Detected"
            case .metricKit: "MetricKit"
            }
        }
    }
#endif
