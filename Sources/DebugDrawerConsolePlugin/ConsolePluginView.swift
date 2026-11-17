#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The plugin's body: search, the toolbar and the lines. The lines are the captured ones, or,
    /// read-only, those of a session an earlier launch kept, under Previous.
    struct ConsolePluginView: View {
        @ObservedObject private var store = ConsoleLogStore.shared
        @ObservedObject private var sessions = ConsoleSessionsModel.shared
        @Environment(\.locale) private var locale
        @Environment(\.timeZone) private var timeZone
        @State private var isFollowing = true
        @State private var searchText = ""

        private var visibleLines: [LogLine] {
            let filtered = store.shownLines
            guard !searchText.isEmpty else { return filtered }
            let query = searchText.lowercased()
            return filtered.filter { $0.text.lowercased().contains(query) }
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                TextField("Search logs...", text: $searchText)
                    .debugDrawerTextFieldStyle()
                    .accessibilityLabel("Search logs")

                if !sessions.sessions.isEmpty {
                    ConsoleLogSourcePicker(source: $store.source)
                }
                if store.source == .previous {
                    ConsolePreviousSessionPicker(
                        sessions: sessions.sessions,
                        shown: store.previousLog,
                        select: { id in Task { await showPrevious(id) } },
                        deleteAll: { Task { await deletePrevious(sessions.sessions.map(\.id)) } }
                    )
                    if let unreadable = sessions.unreadable {
                        DebugDrawerIssueRow("Not read", severity: .error) {
                            Text("The session of \(unreadable.title(locale: locale, timeZone: timeZone)) couldn't be read.")
                        }
                    }
                }

                // Toolbar — filter picker is in its own view to avoid
                // re-creating the NSSegmentedControl on every log batch.
                ConsoleToolbarView(
                    isFollowing: $isFollowing,
                    filterLevel: $store.filterLevel,
                    copyAll: { debugDrawerCopyToClipboard(visibleLines.copiedText) },
                    clear: {
                        if store.source == .previous, let shown = store.previousLog {
                            Task { await deletePrevious([shown.summary.id]) }
                        } else {
                            store.clear()
                        }
                    },
                    source: store.source
                )

                DebugDrawerCodeBlock {
                    ConsoleTextView(
                        lines: visibleLines,
                        isFollowing: $isFollowing
                    )
                    // A new text view for each source and session: the view appends only the
                    // lines past those it drew, which would leave the other source's lines above.
                    .id(shownSession)
                    .frame(minHeight: 120, maxHeight: 300)
                }
            }
            // Listed again each time the plugin shows: writing the current session may have
            // deleted the oldest for room.
            .task { await sessions.reload() }
            // Previous shows the newest session until another is picked.
            .task(id: store.source) {
                if store.source == .previous, store.previousLog == nil, let newest = sessions.sessions.first {
                    await showPrevious(newest.id)
                }
            }
            .onChange(of: sessions.sessions) { _, kept in
                if kept.isEmpty { store.hidePrevious() }
            }
        }

        /// The session the lines are from: `nil` for the captured ones.
        private var shownSession: ConsoleSessionSummary.ID? {
            store.source == .previous ? store.previousLog?.summary.id : nil
        }

        /// Reads the earlier session with `id` and shows its lines.
        private func showPrevious(_ id: ConsoleSessionSummary.ID) async {
            if let log = await sessions.log(of: id) {
                store.showPrevious(log)
            }
        }

        /// Deletes the earlier sessions with `ids`, then shows the newest left, or the captured
        /// lines when none is.
        private func deletePrevious(_ ids: [ConsoleSessionSummary.ID]) async {
            await sessions.delete(ids)
            if let newest = sessions.sessions.first {
                await showPrevious(newest.id)
            } else {
                store.hidePrevious()
            }
        }
    }

    /// Extracted toolbar so the segmented picker doesn't get rebuilt on every log update.
    /// Only `isFollowing` changes frequently — the picker binding (`filterLevel`) is stable and
    /// won't cause the NSSegmentedControl to be recreated. The line count is the header's
    /// accessory, so the toolbar doesn't repeat it.
    struct ConsoleToolbarView: View {
        @Binding var isFollowing: Bool
        @Binding var filterLevel: LogLine.Level
        let copyAll: () -> Void
        /// Clears the captured lines, or, under Previous, deletes the session shown.
        let clear: () -> Void
        /// What the trailing button clears, or for an earlier session, deletes.
        var source = ConsoleLogSource.captured

        var body: some View {
            // The action row wraps what doesn't fit one line, and stacks at accessibility sizes.
            DebugDrawerActionRow {
                ConsoleFilterPicker(filterLevel: $filterLevel)

                if !isFollowing {
                    Button("Resume") { isFollowing = true }
                        .debugDrawerButtonStyle(.borderless)
                        .accessibilityHint("Scrolls to the newest line and follows new ones")
                }

                Button("Copy All", action: copyAll)
            } trailing: {
                Button(source == .previous ? "Delete" : "Clear", role: .destructive, action: clear)
                    .debugDrawerButtonStyle(.destructive)
                    .accessibilityLabel(source == .previous ? "Delete this session" : "Clear the console")
            }
        }
    }

    /// The segmented picker in its own view to prevent SwiftUI from
    /// recreating the NSSegmentedControl when the parent re-renders.
    struct ConsoleFilterPicker: View {
        @Binding var filterLevel: LogLine.Level

        var body: some View {
            Picker("Level", selection: $filterLevel) {
                Text("All").tag(LogLine.Level.debug)
                Text("Info+").tag(LogLine.Level.info)
                Text("Errors").tag(LogLine.Level.error)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Lowest level shown")
            .accessibilityElement(children: .contain)
            .fixedSize()
        }
    }
#endif
