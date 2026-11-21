#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The plugin's body: search, the toolbar, the lines and, under them, what the time range and
    /// the mutes hide. The lines are the captured ones, or, read-only, those of a session an
    /// earlier launch kept, under Previous.
    ///
    /// It draws ``ConsoleModel``'s snapshots from its transport and sends it commands; it keeps
    /// only what is its own: whether the lines follow new ones. Copy All and Copy Line mask what
    /// they copy by the redaction rules of the drawer it is shown in.
    struct ConsolePluginContent: View {
        @StateObject private var transport: DebugDrawerPluginTransport<ConsoleSnapshot, ConsoleCommand>
        /// The drawer the plugin is shown in; `nil` outside any drawer.
        @Environment(\.showingDrawer) private var showingDrawer
        @Environment(\.locale) private var locale
        @Environment(\.timeZone) private var timeZone
        @State private var isFollowing = true
        /// Puts what Copy All and Copy Line copy on the pasteboard.
        private let copyToClipboard: (String) -> Void
        let inspection = Inspection<Self>() // from/for ViewInspector.

        /// - Parameters:
        ///   - transport: Joins the view to the model; made once, for the view's lifetime. The
        ///     shared model's, in the process, unless given.
        ///   - copyToClipboard: Puts copied text on the pasteboard.
        init(
            transport: @escaping @autoclosure () -> DebugDrawerPluginTransport<ConsoleSnapshot, ConsoleCommand> = .direct(to: ConsoleModel.shared),
            copyToClipboard: @escaping (String) -> Void = debugDrawerCopyToClipboard
        ) {
            _transport = StateObject(wrappedValue: transport())
            self.copyToClipboard = copyToClipboard
        }

        var body: some View {
            // The rules a copy is masked by are read from this drawer as the copy happens, rather
            // than through `DebugDrawerRedactionReader`: nothing drawn depends on them, and
            // observing the drawer would draw the log again at each of its changes. Outside any
            // drawer, `DebugDrawer.shared`'s, which the app sets, as the reader picks them.
            let drawer = showingDrawer ?? .shared
            let snapshot = transport.snapshot
            let log = snapshot.log
            let visibleLines = log.shownLines
            VStack(alignment: .leading, spacing: 0) {
                ConsoleSearchField(
                    text: binding(\.log.searchText) { .filter(.setSearchText($0)) },
                    isRegularExpression: binding(\.log.searchIsRegularExpression) { .filter(.setSearchIsRegularExpression($0)) },
                    issue: log.searchIssue
                ) {
                    ConsoleMoreMenu(
                        timeRange: binding(\.log.filter.timeRange) { .filter(.setTimeRange($0)) },
                        mutes: log.filter.mutes,
                        muteChoices: log.muteChoices,
                        mute: { send(.filter(.mute($0))) },
                        unmute: { send(.filter(.unmute($0))) },
                        copyAll: { copyToClipboard(visibleLines.copiedText(redactedBy: drawer.redaction)) }
                    )
                }

                if !snapshot.sessions.isEmpty {
                    ConsoleLogSourcePicker(source: binding(\.log.source) { .lines(.setSource($0)) })
                }
                if log.source == .previous {
                    ConsolePreviousSessionPicker(
                        sessions: snapshot.sessions,
                        shown: log.previousLog,
                        select: { send(.sessions(.show($0))) },
                        deleteAll: { send(.sessions(.delete(snapshot.sessions.map(\.id)))) }
                    )
                    if let unreadable = snapshot.unreadableSession {
                        DebugDrawerIssueRow("Not read", severity: .error) {
                            Text("The session of \(unreadable.title(locale: locale, timeZone: timeZone)) couldn't be read.")
                        }
                    }
                }

                // Toolbar — filter picker is in its own view to avoid
                // re-creating the NSSegmentedControl on every log batch.
                ConsoleToolbarView(
                    isFollowing: $isFollowing,
                    filterLevel: binding(\.log.filter.level) { .filter(.setLevel($0)) },
                    clear: { send(.lines(.clearShown)) },
                    source: log.source
                )
                if let issue = log.muteIssue {
                    DebugDrawerIssueRow("Mutes", status: issue == .notSaved ? "Not saved" : "Not read", severity: .warning) {
                        Text(issue.message)
                    }
                }

                ConsoleLinesWell(lines: visibleLines, isFollowing: $isFollowing) { perform($0, redaction: drawer.redaction) }
                    // A new text view for each source and session, so each opens at its end.
                    .id(shownSession(log))

                switch log.source {
                case .captured:
                    ConsoleDroppedHint(count: log.droppedLineCount)
                case .previous:
                    ConsoleEarlierLinesHint(count: log.previousPage?.earlierCount ?? 0) { send(.lines(.showEarlier)) }
                }
                ConsoleTimeRangeHint(timeRange: log.filter.timeRange) { send(.filter(.setTimeRange(.all))) }
                ConsoleMutedHint(
                    count: log.mutedCount,
                    mutes: log.filter.mutes,
                    isShowing: log.filter.showsMuted,
                    toggle: { send(.filter(.setShowsMuted(!log.filter.showsMuted))) },
                    unmute: { send(.filter(.unmute($0))) },
                    unmuteAll: { send(.filter(.unmuteAll)) }
                )
            }
            // Listed again each time the plugin shows: writing the current session may have
            // deleted the oldest for room.
            .task { send(.sessions(.reload)) }
            // Each source and session opens at its end. Under Previous there is no Resume to
            // follow again, so scrolling up in one session doesn't leave the next scrolled up too.
            .onChange(of: shownSession(log)) { isFollowing = true }
            .onReceive(inspection.notice) { inspection.visit(self, $0) }
        }

        /// The session the lines are from: `nil` for the captured ones.
        private func shownSession(_ log: ConsoleLogSnapshot) -> ConsoleSessionSummary.ID? {
            log.source == .previous ? log.previousLog?.summary.id : nil
        }

        /// Runs what a line's context menu offers; Copy Line masks the line by `redaction`.
        private func perform(_ action: ConsoleLineAction, redaction: DebugDrawerRedaction) {
            switch action {
            case let .copy(line): copyToClipboard(line.copiedText(redactedBy: redaction))
            case let .mute(mute): send(.filter(.mute(mute)))
            case let .showSince(date): send(.filter(.setTimeRange(.since(date))))
            }
        }

        private func send(_ action: ConsoleCommand.Action) {
            transport.send(ConsoleCommand(action))
        }

        /// A binding that reads the latest snapshot at `keyPath` and sends `command` for each
        /// change: read back at once through a direct transport, so a text field never sees its
        /// old value after an edit.
        private func binding<Value>(
            _ keyPath: KeyPath<ConsoleSnapshot, Value>,
            _ command: @escaping (Value) -> ConsoleCommand.Action
        ) -> Binding<Value> {
            Binding(get: { transport.snapshot[keyPath: keyPath] }, set: { send(command($0)) })
        }
    }

    /// Extracted toolbar so the segmented picker doesn't get rebuilt on every log update: the
    /// level, Resume while the captured log doesn't follow new lines (an earlier session gets
    /// none), and Clear at the trailing edge. Copy
    /// All, the time range and the mutes are in More, beside the search field. The line count is
    /// the header's accessory, so the toolbar doesn't repeat it.
    struct ConsoleToolbarView: View {
        @Binding var isFollowing: Bool
        @Binding var filterLevel: LogLine.Level
        /// Clears the captured lines, or, under Previous, deletes the session shown.
        let clear: () -> Void
        /// What the trailing button clears, or for an earlier session, deletes.
        var source = ConsoleLogSource.captured

        var body: some View {
            // The action row wraps what doesn't fit one line, and stacks at accessibility sizes.
            DebugDrawerActionRow {
                ConsoleFilterPicker(filterLevel: $filterLevel)

                if source == .captured, !isFollowing {
                    Button("Resume") { isFollowing = true }
                        .debugDrawerButtonStyle(.borderless)
                        .accessibilityHint("Scrolls to the newest line and follows new ones")
                }
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

    /// The lines in their well, which scrolls once they are taller than it.
    struct ConsoleLinesWell: View {
        let lines: [LogLine]
        @Binding var isFollowing: Bool
        var perform: (ConsoleLineAction) -> Void = { _ in }
        /// The shortest and tallest the well is drawn; both scale with Dynamic Type, as the lines do.
        @ScaledMetric(relativeTo: .body) private var minimumHeight: CGFloat = 120
        @ScaledMetric(relativeTo: .body) private var maximumHeight: CGFloat = 300

        var body: some View {
            DebugDrawerCodeBlock {
                ConsoleTextView(lines: lines, isFollowing: $isFollowing, perform: perform)
                    .frame(minHeight: minimumHeight, maxHeight: maximumHeight)
            }
        }
    }
#endif
