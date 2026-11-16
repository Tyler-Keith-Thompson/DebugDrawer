#if DEBUG
    import Foundation

    /// What delivers a notification request.
    enum NotificationTrigger: Equatable, Sendable {
        /// No trigger: delivered as soon as it is added.
        case immediate
        /// After an interval, once or repeatedly; `next` is when it fires next, if the system
        /// knows.
        case timeInterval(seconds: TimeInterval, repeats: Bool, next: Date?)
        /// When the date's set components match, once or repeatedly.
        case calendar(DateComponents, repeats: Bool, next: Date?)
        /// On entering or leaving a region.
        case location(region: String, repeats: Bool)
        /// APNs delivered it.
        case push
        /// A trigger this build doesn't know, by its class name.
        case other(String)

        /// What the drawer shows for it, with dates in `locale` and `timeZone`.
        func text(locale: Locale, timeZone: TimeZone) -> String {
            switch self {
            case .immediate:
                return "Immediately"
            case let .timeInterval(seconds, repeats, next):
                let interval = Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated))
                return ([repeats ? "Every \(interval)" : "After \(interval)"] + Self.nextText(next, locale: locale, timeZone: timeZone))
                    .joined(separator: ", ")
            case let .calendar(components, repeats, next):
                let matches = "When \(Self.text(of: components))"
                return ([repeats ? "\(matches), repeating" : matches] + Self.nextText(next, locale: locale, timeZone: timeZone))
                    .joined(separator: ", ")
            case let .location(region, repeats):
                return repeats ? "At \(region), repeating" : "At \(region)"
            case .push:
                return "Push"
            case let .other(name):
                return name
            }
        }

        private static func nextText(_ next: Date?, locale: Locale, timeZone: TimeZone) -> [String] {
            guard let next else { return [] }
            var style = Date.FormatStyle(date: .abbreviated, time: .standard, locale: locale)
            style.timeZone = timeZone
            return ["next \(next.formatted(style))"]
        }

        /// The set components, largest first (`hour 9, minute 30`).
        private static func text(of components: DateComponents) -> String {
            let parts: [(String, Int?)] = [
                ("year", components.year), ("month", components.month), ("day", components.day),
                ("weekday", components.weekday), ("hour", components.hour), ("minute", components.minute),
                ("second", components.second)
            ]
            let set = parts.compactMap { name, value in value.map { "\(name) \($0)" } }
            return set.isEmpty ? "any date" : set.joined(separator: ", ")
        }
    }
#endif
