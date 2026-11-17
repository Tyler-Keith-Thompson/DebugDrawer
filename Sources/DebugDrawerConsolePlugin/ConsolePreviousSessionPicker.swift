#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// Under Previous: a menu of the sessions earlier launches kept, by start and size, then the
    /// shown session's app build and line count, and Delete All Sessions.
    struct ConsolePreviousSessionPicker: View {
        /// The sessions kept, the newest first.
        let sessions: [ConsoleSessionSummary]
        /// The session whose lines show; `nil` while it is read.
        let shown: ConsoleSessionLog?
        /// Shows the session with the id.
        let select: (ConsoleSessionSummary.ID) -> Void
        /// Deletes every session kept.
        let deleteAll: () -> Void
        @Environment(\.locale) private var locale
        @Environment(\.timeZone) private var timeZone

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                // The menu has a line of its own: a start to the second and a size, beside a
                // title, would truncate in an iPad's drawer. Under Previous it needs no title.
                // A menu around the picker rather than a menu-style picker, whose label keeps to
                // one line and cuts the start short at accessibility text sizes; this one wraps.
                Menu {
                    Picker("Session", selection: selection) {
                        ForEach(sessions) { session in
                            Text(session.title(locale: locale, timeZone: timeZone)).tag(session.id)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(selectedTitle)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        // A Mac's menu button draws its own indicator; iOS's, Mac Catalyst's
                        // included, draws none, so the label carries the picker's.
                        #if os(iOS)
                            Image(systemName: "chevron.up.chevron.down")
                                .imageScale(.small)
                                .accessibilityHidden(true)
                        #endif
                    }
                }
                .accessibilityLabel("Session")
                .accessibilityValue(selectedTitle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .debugDrawerRowPadding()
                if let shown {
                    if let header = shown.header {
                        DebugDrawerKeyValueRow("App", value: [header.app, header.appVersion].filter { !$0.isEmpty }.joined(separator: " "))
                            .debugDrawerValueStyle(.text)
                    }
                    DebugDrawerKeyValueRow("Lines", value: "\(shown.lines.count.formatted()), read-only")
                        .debugDrawerValueStyle(.text)
                    if shown.skippedLines > 0 {
                        // The last line of a session the app crashed while writing is torn.
                        DebugDrawerKeyValueRow("Unreadable", value: shown.skippedLines == 1 ? "1 line" : "\(shown.skippedLines.formatted()) lines")
                            .debugDrawerValueStyle(.text)
                    }
                }
                DebugDrawerActionRow {
                    EmptyView()
                } trailing: {
                    Button("Delete All Sessions", role: .destructive, action: deleteAll)
                        .debugDrawerButtonStyle(.destructive)
                        .accessibilityLabel("Delete All Sessions")
                        .accessibilityHint("Deletes the log lines every earlier launch kept")
                }
            }
        }

        /// The selected session's start and size.
        private var selectedTitle: String {
            sessions.first { $0.id == selection.wrappedValue }?.title(locale: locale, timeZone: timeZone) ?? ""
        }

        /// The shown session, or the newest while none is.
        private var selection: Binding<ConsoleSessionSummary.ID> {
            Binding(
                get: { shown?.summary.id ?? sessions.first?.id ?? "" },
                set: { select($0) }
            )
        }
    }
#endif
