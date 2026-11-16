#if DEBUG
    import Foundation

    /// A class with instances alive that shouldn't be: view controllers whose screen was dismissed,
    /// or more tracked objects than the class allows.
    struct LeakSuspect: Equatable, Identifiable, Sendable {
        /// Why the instances are suspects.
        enum Reason: Hashable, Sendable {
            /// View controllers still alive a run-loop turn after their screen was dismissed.
            case aliveAfterDismissal
            /// More objects alive than `LeakDetector.trackLifetime(of:maxCount:)` allows.
            case overLimit(maxCount: Int)
        }

        let type: TrackedClass
        let reason: Reason
        /// How many instances are suspects: the dismissed ones still alive, or every one alive
        /// over the limit.
        let count: Int
        /// When the class was first flagged for this reason.
        let since: Date

        /// One suspect per class and kind of reason, so a view controller over its own limit and
        /// alive after dismissal is listed twice.
        var id: String {
            switch reason {
            case .aliveAfterDismissal: "dismissed:\(type.qualifiedName)"
            case .overLimit: "limit:\(type.qualifiedName)"
            }
        }
    }

    extension LeakSuspect {
        /// What is wrong, in a few words: `2 still alive after dismissal`, `3 alive, at most 1
        /// expected`.
        var summary: String {
            switch reason {
            case .aliveAfterDismissal: "\(count) still alive after dismissal"
            case let .overLimit(maxCount): "\(count) alive, at most \(maxCount) expected"
            }
        }

        /// The toast posted when the class is flagged, or its count grows.
        var toastMessage: String {
            switch reason {
            case .aliveAfterDismissal: "\(type.name) is still alive after it was dismissed"
            case let .overLimit(maxCount): "\(count) \(type.name) instances alive, at most \(maxCount) expected"
            }
        }

        /// The suspect as text: its class with the module, what is wrong, and since when.
        func text(dateFormat: Date.ISO8601FormatStyle = .iso8601) -> String {
            [type.qualifiedName, summary, "Flagged: \(since.formatted(dateFormat))"].joined(separator: "\n") + "\n"
        }
    }
#endif
