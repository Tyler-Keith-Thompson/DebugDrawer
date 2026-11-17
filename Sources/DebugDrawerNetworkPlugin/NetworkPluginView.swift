#if DEBUG
    import DebugDrawer
    import SwiftUI
    import UniformTypeIdentifiers

    /// The plugin's body: the request log, the WebSocket connections, the Mocks, Conditions and
    /// Ignored hosts sections, or the editor of one mock or condition while it is open. The log
    /// shows the captured requests, or, read-only, those of a session an earlier launch kept or of
    /// an imported HAR file, without those to an ignored host until a note under it shows them.
    struct NetworkPluginView: View {
        /// What the plugin shows: the log and its sections, or one editor in their place until it
        /// is saved or cancelled.
        enum Screen {
            case requests
            case mock(NetworkMockDraft)
            case condition(NetworkConditionDraft)
            case resend(NetworkReplayDraft)
        }

        @ObservedObject private var store = NetworkStore.shared
        @ObservedObject private var mocks = NetworkMocksModel.shared
        @ObservedObject private var conditions = NetworkConditionsModel.shared
        @ObservedObject private var replays = NetworkReplayModel.shared
        @ObservedObject private var drawer = DebugDrawer.shared
        @ObservedObject private var sessions = NetworkSessionsModel.shared
        @Environment(\.locale) private var locale
        @Environment(\.timeZone) private var timeZone
        @State private var selectedId: UUID?
        @State private var selectedWebSocket: NetworkWebSocketConnection.ID?
        @State private var selectedRule: NetworkMockRule.ID?
        @State private var selectedProfile: NetworkConditionProfile.ID?
        @State private var screen = Screen.requests
        @State private var isImporting = false

        var body: some View {
            switch screen {
            case .requests:
                requests
            case let .mock(draft):
                NetworkMockEditor(
                    draft: draft,
                    importBody: { mocks.importBody(from: $0) },
                    cancel: { screen = .requests },
                    save: { rule in
                        mocks.save(rule)
                        selectedRule = rule.id
                        screen = .requests
                    }
                )
                // A new draft starts from its own fields, not the last one's.
                .id(draft.id)
            case let .condition(draft):
                NetworkConditionEditor(
                    draft: draft,
                    cancel: { screen = .requests },
                    save: { profile in
                        conditions.save(profile)
                        selectedProfile = profile.id
                        screen = .requests
                    }
                )
                .id(draft.id)
            case let .resend(draft):
                NetworkReplayEditor(
                    draft: draft,
                    cancel: { screen = .requests },
                    send: { request in
                        selectedId = draft.original
                        screen = .requests
                        Task { await replays.resend(request, replaying: draft.original) }
                    }
                )
                .id(draft.id)
            }
        }

        private var requests: some View {
            VStack(alignment: .leading, spacing: 0) {
                // The request count is in the header; the rates are an inspector form here.
                let shown = store.shownEntries
                if !shown.isEmpty {
                    let stats = NetworkStats(shown)
                    DebugDrawerKeyValueRow("Succeeded", value: stats.successRate)
                    DebugDrawerKeyValueRow("Average", value: stats.averageTime)
                }

                let sources = shownSources
                if sources.count > 1 {
                    NetworkLogSourcePicker(
                        source: $store.source,
                        fileName: store.importedLog?.fileName ?? "",
                        count: store.importedLog?.entries.count ?? 0,
                        sources: sources
                    )
                }
                if store.source == .previous {
                    NetworkPreviousSessionPicker(
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

                let filtered = store.filteredEntries
                let webSockets = store.filteredWebSockets
                NetworkToolbar(
                    filterStatus: $store.filterStatus,
                    clear: {
                        if store.source == .previous, let shown = store.previousLog {
                            Task { await deletePrevious([shown.summary.id]) }
                        } else {
                            store.clearShown()
                        }
                    },
                    export: NetworkArchiveFile(entries: filtered, redaction: drawer.redaction, webSockets: webSockets),
                    isFiltered: filtered.count < shown.count || webSockets.count < store.shownWebSockets.count,
                    importArchive: { isImporting = true },
                    source: store.source
                )

                if let issue = store.importIssue {
                    DebugDrawerIssueRow("Not imported", severity: .error) {
                        Text(issue.message)
                    }
                }

                DebugDrawerSearchableList(
                    "Filter URL...",
                    text: $store.filterText,
                    accessibilityLabel: "Filter requests by URL, method, GraphQL operation or response",
                    maxHeight: 300
                ) {
                    // An earlier session's and an imported file's requests are read-only: they can
                    // be mocked, but not resent, since their credentials are masked and a replay
                    // belongs with the captured requests, apart from its original.
                    let isReadOnly = store.source.isReadOnly
                    ForEach(filtered) { entry in
                        let isSelected = selectedId == entry.id
                        NetworkRequestRow(
                            entry: entry, redaction: drawer.redaction, isSelected: isSelected,
                            onSelect: { selectedId = isSelected ? nil : entry.id },
                            onMock: { screen = .mock(NetworkMockDraft(mocks.rule(mocking: $0), isNew: true)) },
                            onResend: isReadOnly ? nil : { entry in Task { await replays.resend(entry) } },
                            onEditAndResend: isReadOnly ? nil : { screen = .resend(NetworkReplayDraft($0)) },
                            onShow: { selectedId = $0 },
                            // Only the open detail shows the links, so only its are worked out.
                            links: isSelected && !isReadOnly ? NetworkReplayLinks(of: entry, in: store.entries) : .none,
                            replayStatus: isReadOnly ? nil : replays.statuses[entry.id],
                            // A host the list ignores already, shown with Show, has nothing to add.
                            onIgnore: isSelected && !store.ignoredDomains.ignores(host: entry.host) ? { store.ignore($0) } : nil
                        )
                    }
                }
                .fileImporter(isPresented: $isImporting, allowedContentTypes: UTType.importableArchives) { result in
                    if case let .success(url) = result {
                        store.importArchive(from: url)
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

                NetworkIgnoredHint(count: store.ignoredCount, isShowing: store.showsIgnored) {
                    store.showsIgnored.toggle()
                }

                // WebSocket traffic bypasses the URL protocol, so its connections are listed
                // apart from the requests, under the same filters.
                NetworkWebSocketsSection(connections: webSockets, redaction: drawer.redaction, selected: $selectedWebSocket)

                // Below the log, which is what the plugin is opened for most often.
                NetworkMocksSection(
                    rules: mocks.rules,
                    issue: mocks.issue,
                    selected: $selectedRule,
                    setEnabled: { mocks.setEnabled($1, id: $0) },
                    add: { screen = .mock(.new()) },
                    edit: { screen = .mock(NetworkMockDraft($0, isNew: false)) },
                    move: { mocks.move($0, by: $1) },
                    delete: { mocks.delete($0) }
                )

                NetworkConditionsSection(
                    profiles: conditions.profiles,
                    issue: conditions.issue,
                    selected: $selectedProfile,
                    setEnabled: { conditions.setEnabled($1, id: $0) },
                    add: { screen = .condition(.new()) },
                    edit: { screen = .condition(NetworkConditionDraft($0, isNew: false)) },
                    move: { conditions.move($0, by: $1) },
                    delete: { conditions.delete($0) }
                )

                NetworkIgnoreListSection(
                    domains: store.ignoredDomains,
                    issue: store.ignoreIssue,
                    add: { store.ignore($0) },
                    remove: { store.stopIgnoring($0) }
                )
            }
        }

        /// The segments the source picker offers: Captured, then Previous while an earlier launch's
        /// session is kept, and Imported while a file is.
        private var shownSources: [NetworkLogSource] {
            NetworkLogSource.allCases.filter { source in
                switch source {
                case .captured: true
                case .previous: !sessions.sessions.isEmpty
                case .imported: store.importedLog != nil
                }
            }
        }

        /// Reads the earlier session with `id` and shows its requests.
        private func showPrevious(_ id: NetworkSessionSummary.ID) async {
            if let log = await sessions.log(of: id) {
                selectedId = nil
                store.showPrevious(log)
            }
        }

        /// Deletes the earlier sessions with `ids`, then shows the newest left, or the captured
        /// requests when none is.
        private func deletePrevious(_ ids: [NetworkSessionSummary.ID]) async {
            await sessions.delete(ids)
            if let newest = sessions.sessions.first {
                await showPrevious(newest.id)
            } else {
                store.hidePrevious()
            }
        }
    }

    /// A request's method, status, path and duration, after an error glyph when it failed, and a
    /// GraphQL request's operation below them; selected, it shows the request's detail.
    struct NetworkRequestRow: View {
        let entry: NetworkEntry
        let redaction: DebugDrawerRedaction
        let isSelected: Bool
        let onSelect: () -> Void
        /// Opens a new mock made from the request; `nil` offers no Mock This.
        var onMock: ((NetworkEntry) -> Void)?
        /// Sends the request again, unchanged; `nil` offers no Resend.
        var onResend: ((NetworkEntry) -> Void)?
        /// Opens the request in the resend editor; `nil` offers no Edit and Resend.
        var onEditAndResend: ((NetworkEntry) -> Void)?
        /// Selects the request with the id, for the links to a replay's original and its replays.
        var onShow: ((NetworkEntry.ID) -> Void)?
        /// The requests this one is linked to by replay.
        var links = NetworkReplayLinks.none
        /// Where the last resend of this request stands, if one hasn't got its answer.
        var replayStatus: NetworkReplayStatus?
        /// Adds the request's host, or a parent domain, to the ignore list; `nil` offers no Ignore.
        var onIgnore: ((NetworkIgnoredDomain) -> Void)?
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                Button(action: onSelect) {
                    VStack(alignment: .leading, spacing: 1) {
                        // At accessibility text sizes the path and the duration have no room beside
                        // the method and status, so each takes a line of its own.
                        let layout = dynamicTypeSize.isAccessibilitySize
                            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 1))
                            : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
                        layout {
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(alignment: .firstTextBaseline) {
                                    glyph
                                    Text(entry.method)
                                        .debugDrawerFont(.code)
                                        .debugDrawerForegroundStyle(.secondary)
                                    status
                                    if !badgesOnOwnLine {
                                        badges
                                    }
                                }
                                if badgesOnOwnLine, badgeCount > 0 {
                                    HStack { badges }
                                }
                            }
                            // A few short words that never wrap: the path gives way to them instead.
                            .fixedSize(horizontal: true, vertical: false)
                            Text(entry.path)
                                .debugDrawerFont(.code)
                                .debugDrawerForegroundStyle(.primary)
                                .lineLimit(3)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            duration
                        }
                        // Every GraphQL request has the same path, so its operation names it, on
                        // a line of its own: beside the method, status and badges it would get a
                        // few letters' width in an iPad's drawer and lose its middle.
                        if let operation = entry.graphQLOperationName {
                            HStack(alignment: .firstTextBaseline) {
                                glyph.hidden()
                                Text(operation)
                                    .debugDrawerFont(.code)
                                    .debugDrawerForegroundStyle(.primary)
                                    .lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .debugDrawerRowPadding()
                    .contentShape(Rectangle())
                }
                .debugDrawerButtonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])

                if isSelected {
                    NetworkRequestDetail(
                        entry: entry, redaction: redaction, onMock: onMock, onResend: onResend, onEditAndResend: onEditAndResend,
                        onShow: onShow, links: links, replayStatus: replayStatus, onIgnore: onIgnore
                    )
                }
            }
        }

        /// The error glyph for a failed request; for any other, the same space left empty (or a
        /// spinner while it runs), so methods line up from row to row.
        private var glyph: some View {
            DebugDrawerIssueGlyph(.error)
                .opacity(entry.isFailure ? 1 : 0)
                .accessibilityHidden(!entry.isFailure)
                .overlay {
                    if !entry.isComplete {
                        ProgressView()
                            .controlSize(.mini)
                            .accessibilityLabel("In progress")
                    }
                }
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - $0.height * 0.15 }
        }

        /// Whether the badges take a line of their own: at accessibility text sizes, where they
        /// would squeeze the status, and when two or more show, since two beside the method and
        /// status leave the path a letter's width in a phone-wide drawer.
        private var badgesOnOwnLine: Bool {
            dynamicTypeSize.isAccessibilitySize || badgeCount > 1
        }

        private var badgeCount: Int {
            [entry.replayOf != nil, entry.mockRuleName != nil, entry.conditionEffect != nil].count(where: \.self)
        }

        /// Replay, Mocked and Conditioned, for a request the drawer resent, a mock answered or a
        /// profile conditioned.
        @ViewBuilder private var badges: some View {
            if entry.replayOf != nil {
                NetworkReplayBadge()
            }
            if entry.mockRuleName != nil {
                NetworkMockedBadge()
            }
            if entry.conditionEffect != nil {
                NetworkConditionedBadge()
            }
        }

        @ViewBuilder private var status: some View {
            if let code = entry.statusCode {
                Text(String(code))
                    .debugDrawerFont(.value)
                    .debugDrawerForegroundStyle(entry.isFailure ? .error : .primary)
            } else if entry.isComplete {
                Text("ERR")
                    .debugDrawerFont(.value)
                    .debugDrawerForegroundStyle(.error)
            }
        }

        private var duration: some View {
            Text(entry.durationLabel)
                .debugDrawerFont(.value)
                .debugDrawerForegroundStyle(.tertiary)
        }
    }
#endif
