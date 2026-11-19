#if DEBUG
    /// A subsystem, or one category of a subsystem, whose os_log lines the console hides.
    ///
    /// A category is muted within its subsystem: categories are named per subsystem
    /// (`networking` in two frameworks is two categories), so muting one leaves the other.
    enum ConsoleMute: Hashable, Codable, Sendable {
        /// Every line logged to the subsystem (`com.example.shop`).
        case subsystem(String)
        /// The lines logged to the category in the subsystem.
        case category(String, subsystem: String)

        /// Whether the mute hides `line`.
        func matches(_ line: LogLine) -> Bool {
            switch self {
            case let .subsystem(subsystem): line.subsystem == subsystem
            case let .category(category, subsystem): line.subsystem == subsystem && line.category == category
            }
        }

        /// The mute as the console names it: `com.example.shop`, or `com.example.shop: networking`.
        var title: String {
            switch self {
            case let .subsystem(subsystem): subsystem
            case let .category(category, subsystem): "\(subsystem): \(category)"
            }
        }

        /// The mutes a person can add for `line`, its subsystem then its category; none for a line
        /// without a subsystem, as stdout and stderr lines are.
        static func choices(for line: LogLine) -> [ConsoleMute] {
            guard !line.subsystem.isEmpty else { return [] }
            let subsystem = ConsoleMute.subsystem(line.subsystem)
            return line.category.isEmpty ? [subsystem] : [subsystem, .category(line.category, subsystem: line.subsystem)]
        }

        /// The mutes the menu offers for `lines`: each subsystem they were logged to, then each
        /// category, sorted by name, without those `mutes` hold or that a muted subsystem covers.
        ///
        /// - Complexity: O(*n*) in the number of lines, plus sorting the choices.
        static func choices(in lines: [LogLine], excluding mutes: [ConsoleMute]) -> [ConsoleMute] {
            var subsystems: Set<String> = []
            var categories: Set<ConsoleMute> = []
            for line in lines where !line.subsystem.isEmpty {
                subsystems.insert(line.subsystem)
                if !line.category.isEmpty {
                    categories.insert(.category(line.category, subsystem: line.subsystem))
                }
            }
            let muted = Set(mutes)
            let open = subsystems.map(ConsoleMute.subsystem).filter { !muted.contains($0) }
            let openCategories = categories.filter { category in
                guard case let .category(_, subsystem) = category else { return false }
                return !muted.contains(category) && !muted.contains(.subsystem(subsystem))
            }
            return open.sorted { $0.title < $1.title } + openCategories.sorted { $0.title < $1.title }
        }

        /// Whether this mutes a whole subsystem rather than one category of it.
        var isSubsystem: Bool {
            if case .subsystem = self { true } else { false }
        }
    }

    extension [ConsoleMute] {
        /// Whether one of the mutes hides `line`.
        func mutes(_ line: LogLine) -> Bool {
            !isEmpty && !line.subsystem.isEmpty && contains { $0.matches(line) }
        }
    }
#endif
