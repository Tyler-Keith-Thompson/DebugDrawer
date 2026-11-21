#if DEBUG
    import Foundation

    /// What a line's context menu offers: copying it, muting its subsystem or its category, and
    /// showing the lines from it on.
    enum ConsoleLineAction: Equatable {
        /// Copies the line as Copy All copies it, masked by the drawer's redaction rules.
        case copy(LogLine)
        /// Hides the lines the mute matches.
        case mute(ConsoleMute)
        /// Limits the list to the lines logged at the date or later.
        case showSince(Date)

        /// The actions for `line`: Copy Line, Mute Subsystem and Mute Category when it has them,
        /// then Show Since This Line.
        static func actions(for line: LogLine) -> [ConsoleLineAction] {
            [.copy(line)] + ConsoleMute.choices(for: line).map(ConsoleLineAction.mute) + [.showSince(line.timestamp)]
        }

        /// The menu item's title.
        var title: String {
            switch self {
            case .copy: "Copy Line"
            case let .mute(.subsystem(subsystem)): "Mute Subsystem “\(subsystem)”"
            case let .mute(.category(category, _)): "Mute Category “\(category)”"
            case .showSince: "Show Since This Line"
            }
        }
    }

    extension LogLine {
        /// The subsystem and category as each line shows them, short: the subsystem's last
        /// component and the category, `feed/networking`; `nil` for a line without either. The
        /// menus and copied text name the subsystem in full.
        var shownOrigin: String? {
            let subsystem = subsystem.split(separator: ".").last.map(String.init) ?? ""
            switch (subsystem.isEmpty, category.isEmpty) {
            case (true, true): return nil
            case (false, true): return subsystem
            case (true, false): return category
            case (false, false): return "\(subsystem)/\(category)"
            }
        }
    }
#endif
