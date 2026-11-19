#if DEBUG
    import Foundation

    /// Which stretch of time the console lists lines from: all of it, the last minutes before the
    /// newest line, or everything from a line on.
    ///
    /// "Last 5 Minutes" counts back from the newest line rather than from the clock, so it reads an
    /// earlier session's last five minutes as it does the current one's, and the window moves as
    /// lines arrive, with no timer to move it.
    enum ConsoleTimeRange: Hashable, Codable, Sendable {
        /// Every line.
        case all
        /// The lines logged in the minutes up to the newest line.
        case last(minutes: Int)
        /// The lines logged at the date or later.
        case since(Date)

        /// The ranges the menu offers; "Since This Line" is a line's own action.
        static let presets: [ConsoleTimeRange] = [.all, .last(minutes: 1), .last(minutes: 5), .last(minutes: 15)]

        /// The earliest time a line may be logged at to show; `nil` for no limit.
        ///
        /// - Parameter newest: When the newest line of those shown was logged; `nil` when there
        ///   are none.
        func start(newest: Date?) -> Date? {
            switch self {
            case .all: nil
            case let .last(minutes): newest.map { $0.addingTimeInterval(-Double(minutes) * 60) }
            case let .since(date): date
            }
        }

        /// The range as the menu names it: "All", "Last 5 Minutes", "Since 09:41:02.250".
        var title: String {
            switch self {
            case .all: "All"
            case .last(minutes: 1): "Last Minute"
            case let .last(minutes): "Last \(minutes) Minutes"
            case let .since(date): "Since \(Self.timeFormatter.string(from: date))"
            }
        }

        /// The console's line times, `HH:mm:ss.SSS`, local.
        private static let timeFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss.SSS"
            return formatter
        }()
    }
#endif
