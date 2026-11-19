#if DEBUG
    import DebugDrawer
    import SwiftUI
    import UniformTypeIdentifiers

    /// The plugin's body: the request log, the WebSocket connections, the Mocks, Conditions and
    /// Ignored hosts sections, or the editor of one mock or condition while it is open. The log
    /// shows the captured requests, or, read-only, those of a session an earlier launch kept or of
    /// an imported HAR file, without those to an ignored host until a note under it shows them.
    ///
    /// It draws ``NetworkModel``'s snapshots from its transport and sends it commands; it keeps
    /// only what is its own: the selection, the editor open and whether the file importer is.
    struct NetworkPluginView: View {
        /// What the plugin shows: the log and its sections, or one editor in their place until it
        /// is saved or cancelled.
        enum Screen {
            case requests
            case mock(NetworkMockDraft)
            case condition(NetworkConditionDraft)
            case resend(NetworkReplayDraft)
        }

        @StateObject private var transport: DebugDrawerPluginTransport<NetworkSnapshot, NetworkCommand>
        // The drawer's redaction rules, which mask what the rows show and what an export holds.
        @ObservedObject private var drawer = DebugDrawer.shared
        @Environment(\.locale) private var locale
        @Environment(\.timeZone) private var timeZone
        @State private var selectedId: UUID?
        @State private var selectedWebSocket: NetworkWebSocketConnection.ID?
        @State private var selectedRule: NetworkMockRule.ID?
        @State private var selectedProfile: NetworkConditionProfile.ID?
        @State private var screen = Screen.requests
        @State private var isImporting = false

        /// - Parameter transport: Joins the view to the model; made once, for the view's lifetime.
        init(transport: @escaping @autoclosure () -> DebugDrawerPluginTransport<NetworkSnapshot, NetworkCommand>) {
            _transport = StateObject(wrappedValue: transport())
        }

        var body: some View {
            switch screen {
            case .requests:
                requests(transport.snapshot)
            case let .mock(draft):
                NetworkMockEditor(
                    draft: draft,
                    importBody: importBody,
                    cancel: { screen = .requests },
                    save: { rule in
                        send(.mocks(.save(rule)))
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
                        send(.conditions(.save(profile)))
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
                        if let request = NetworkReplayRequest(request) {
                            send(.replays(.resendEdited(request, original: draft.original)))
                        }
                    }
                )
                .id(draft.id)
            }
        }

        private func requests(_ snapshot: NetworkSnapshot) -> some View {
            let log = snapshot.log
            return VStack(alignment: .leading, spacing: 0) {
                sourceRows(snapshot)

                let shown = log.shownEntries
                let filtered = log.filteredEntries
                let webSockets = log.filteredWebSockets
                NetworkToolbar(
                    filterStatus: binding(\.log.filterStatus) { .log(.setFilterStatus($0)) },
                    clear: { send(.log(.clearShown)) },
                    export: NetworkArchiveFile(entries: filtered, redaction: drawer.redaction, webSockets: webSockets),
                    isFiltered: filtered.count < shown.count || webSockets.count < log.shownWebSockets.count,
                    importArchive: { isImporting = true },
                    source: log.source
                )

                if let issue = log.importIssue {
                    DebugDrawerIssueRow("Not imported", severity: .error) {
                        Text(issue.message)
                    }
                }

                requestList(snapshot, entries: filtered)

                NetworkIgnoredHint(count: log.ignoredCount, isShowing: log.showsIgnored) {
                    send(.log(.setShowsIgnored(!log.showsIgnored)))
                }

                // WebSocket traffic bypasses the URL protocol, so its connections are listed
                // apart from the requests, under the same filters.
                NetworkWebSocketsSection(connections: webSockets, redaction: drawer.redaction, selected: $selectedWebSocket)

                // Below the log, which is what the plugin is opened for most often.
                sections(snapshot)
            }
        }

        /// The rates of the requests shown, the source picker and, under Previous, the session
        /// picker.
        @ViewBuilder private func sourceRows(_ snapshot: NetworkSnapshot) -> some View {
            let log = snapshot.log
            // The request count is in the header; the rates are an inspector form here.
            let shown = log.shownEntries
            if !shown.isEmpty {
                let stats = NetworkStats(shown)
                DebugDrawerKeyValueRow("Succeeded", value: stats.successRate)
                DebugDrawerKeyValueRow("Average", value: stats.averageTime)
            }

            let sources = snapshot.availableSources
            if sources.count > 1 {
                NetworkLogSourcePicker(
                    source: binding(\.log.source) { .log(.setSource($0)) },
                    fileName: log.imported?.fileName ?? "",
                    count: log.imported?.entries.count ?? 0,
                    sources: sources
                )
            }
            if log.source == .previous {
                NetworkPreviousSessionPicker(
                    sessions: snapshot.sessions,
                    shown: log.previous,
                    select: { send(.sessions(.show($0))) },
                    deleteAll: { send(.sessions(.delete(snapshot.sessions.map(\.id)))) }
                )
                if let unreadable = snapshot.unreadableSession {
                    DebugDrawerIssueRow("Not read", severity: .error) {
                        Text("The session of \(unreadable.title(locale: locale, timeZone: timeZone)) couldn't be read.")
                    }
                }
            }
        }

        /// The filter field and the requests that pass it.
        private func requestList(_ snapshot: NetworkSnapshot, entries filtered: [NetworkEntry]) -> some View {
            let log = snapshot.log
            return DebugDrawerSearchableList(
                "Filter URL...",
                text: binding(\.log.filterText) { .log(.setFilterText($0)) },
                accessibilityLabel: "Filter requests by URL, method, GraphQL operation or response",
                maxHeight: 300
            ) {
                // An earlier session's and an imported file's requests are read-only: they can
                // be mocked, but not resent, since their credentials are masked and a replay
                // belongs with the captured requests, apart from its original.
                let isReadOnly = log.source.isReadOnly
                ForEach(filtered) { entry in
                    let isSelected = selectedId == entry.id
                    NetworkRequestRow(
                        entry: entry, redaction: drawer.redaction, isSelected: isSelected,
                        onSelect: { selectedId = isSelected ? nil : entry.id },
                        onMock: { mock($0) },
                        onResend: isReadOnly ? nil : { send(.replays(.resend($0.id))) },
                        onEditAndResend: isReadOnly ? nil : { screen = .resend(NetworkReplayDraft($0)) },
                        onShow: { selectedId = $0 },
                        // Only the open detail shows the links, so only its are worked out.
                        links: isSelected && !isReadOnly ? NetworkReplayLinks(of: entry, in: log.captured) : .none,
                        replayStatus: isReadOnly ? nil : snapshot.replayStatuses[entry.id],
                        // A host the list ignores already, shown with Show, has nothing to add.
                        onIgnore: isSelected && !log.ignoredDomains.ignores(host: entry.host) ? { send(.log(.ignore($0))) } : nil
                    )
                }
            }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: UTType.importableArchives) { result in
                if case let .success(url) = result {
                    send(.log(.importArchive(url)))
                }
            }
            // Listed again each time the plugin shows: writing the current session may have
            // deleted the oldest for room.
            .task { send(.sessions(.reload)) }
            // Another session's requests have other ids, so nothing stays selected.
            .onChange(of: log.previous?.summary.id) { _, shown in
                if shown != nil { selectedId = nil }
            }
        }

        /// The Mocks, Conditions and Ignored hosts sections.
        @ViewBuilder private func sections(_ snapshot: NetworkSnapshot) -> some View {
            NetworkMocksSection(
                rules: snapshot.mockRules,
                issue: snapshot.mocksIssue,
                selected: $selectedRule,
                setEnabled: { send(.mocks(.setEnabled($0, $1))) },
                add: { screen = .mock(.new()) },
                edit: { screen = .mock(NetworkMockDraft($0, isNew: false)) },
                move: { send(.mocks(.move($0, offset: $1))) },
                delete: { send(.mocks(.delete($0))) }
            )

            NetworkConditionsSection(
                profiles: snapshot.conditionProfiles,
                issue: snapshot.conditionsIssue,
                selected: $selectedProfile,
                setEnabled: { send(.conditions(.setEnabled($0, $1))) },
                add: { screen = .condition(.new()) },
                edit: { screen = .condition(NetworkConditionDraft($0, isNew: false)) },
                move: { send(.conditions(.move($0, offset: $1))) },
                delete: { send(.conditions(.delete($0))) }
            )

            NetworkIgnoreListSection(
                domains: snapshot.log.ignoredDomains,
                issue: snapshot.log.ignoreIssue,
                add: { send(.log(.ignore($0))) },
                remove: { send(.log(.stopIgnoring($0))) }
            )
        }

        /// Opens the mock editor on a rule that answers like `entry`; a body that isn't text goes
        /// to the storage first, as the file the rule names.
        private func mock(_ entry: NetworkEntry) {
            let prefill = NetworkMockPrefill(mocking: entry)
            if let upload = prefill.upload {
                send(.mocks(.addBody(upload)))
            }
            screen = .mock(NetworkMockDraft(prefill.rule, isNew: true))
        }

        /// Reads the file the user chose for a mock's body and sends it to the storage; its name,
        /// for the draft, or `nil` when it can't be read.
        private func importBody(from url: URL) -> String? {
            guard let upload = NetworkMockBodyUpload(contentsOf: url) else {
                send(.mocks(.bodyUnreadable))
                return nil
            }
            send(.mocks(.addBody(upload)))
            return upload.name
        }

        private func send(_ action: NetworkCommand.Action) {
            transport.send(NetworkCommand(action))
        }

        /// A binding that reads the latest snapshot at `keyPath` and sends `command` for each
        /// change: read back at once through a direct transport, so a text field never sees its
        /// old value after an edit.
        private func binding<Value>(
            _ keyPath: KeyPath<NetworkSnapshot, Value>,
            _ command: @escaping (Value) -> NetworkCommand.Action
        ) -> Binding<Value> {
            Binding(get: { transport.snapshot[keyPath: keyPath] }, set: { send(command($0)) })
        }
    }
#endif
