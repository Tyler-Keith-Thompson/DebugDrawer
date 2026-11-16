#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// One suspect as an issue row: a warning glyph, its class, how many are alive and why that's
    /// wrong, what kind of object it is and when it was flagged, and a button that ignores the
    /// class.
    struct LeakRow: View {
        let suspect: LeakSuspect
        let onIgnore: () -> Void
        @Environment(\.locale) private var locale
        @Environment(\.timeZone) private var timeZone

        var body: some View {
            DebugDrawerIssueRow(suspect.type.name, severity: .warning) {
                Text(suspect.summary)
                Text(facts)
            } accessory: {
                Button("Ignore", action: onIgnore)
                    .debugDrawerButtonStyle(.borderless)
                    .accessibilityLabel("Ignore \(suspect.type.name)")
                    .accessibilityHint("Stops showing and counting this class's suspects")
            }
        }

        /// What kind of suspect, and since when.
        private var facts: String {
            let date = suspect.since.formatted(Date.FormatStyle(date: .abbreviated, time: .standard, locale: locale, timeZone: timeZone))
            return "\(suspect.reason.title) · flagged \(date)"
        }
    }

    extension LeakSuspect.Reason {
        /// What kind of object the suspect is, as the drawer names it.
        fileprivate var title: String {
            switch self {
            case .aliveAfterDismissal: "View controller"
            case .overLimit: "Tracked object"
            }
        }
    }
#endif
