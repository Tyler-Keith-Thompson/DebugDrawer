#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// When a file or folder was modified and created, as inspector rows, in the environment's
    /// locale and time zone.
    struct FileDateRows: View {
        let item: FileItem
        @Environment(\.locale) private var locale
        @Environment(\.timeZone) private var timeZone

        var body: some View {
            Group {
                if let modified = item.modified {
                    DebugDrawerKeyValueRow("Modified", value: text(modified))
                }
                if let created = item.created {
                    DebugDrawerKeyValueRow("Created", value: text(created))
                }
            }
            // A date is data, set in the value type like the size above it.
            .debugDrawerValueStyle(.code)
        }

        private func text(_ date: Date) -> String {
            date.formatted(Date.FormatStyle(date: .abbreviated, time: .standard, locale: locale, timeZone: timeZone))
        }
    }
#endif
