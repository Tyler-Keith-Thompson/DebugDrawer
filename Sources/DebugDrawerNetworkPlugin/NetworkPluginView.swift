#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The plugin's body: the request log, the Mocks section and the Conditions section, or the
    /// editor of one mock or condition while it is open.
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
        @State private var selectedId: UUID?
        @State private var selectedRule: NetworkMockRule.ID?
        @State private var selectedProfile: NetworkConditionProfile.ID?
        @State private var screen = Screen.requests

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
                if !store.entries.isEmpty {
                    let stats = NetworkStats(store.entries)
                    DebugDrawerKeyValueRow("Succeeded", value: stats.successRate)
                    DebugDrawerKeyValueRow("Average", value: stats.averageTime)
                }

                NetworkToolbar(filterStatus: $store.filterStatus) { store.clear() }

                DebugDrawerSearchableList(
                    "Filter URL...",
                    text: $store.filterText,
                    accessibilityLabel: "Filter requests by URL, method or response",
                    maxHeight: 300
                ) {
                    ForEach(store.filteredEntries) { entry in
                        let isSelected = selectedId == entry.id
                        NetworkRequestRow(
                            entry: entry, redaction: drawer.redaction, isSelected: isSelected,
                            onSelect: { selectedId = isSelected ? nil : entry.id },
                            onMock: { screen = .mock(NetworkMockDraft(mocks.rule(mocking: $0), isNew: true)) },
                            onResend: { entry in Task { await replays.resend(entry) } },
                            onEditAndResend: { screen = .resend(NetworkReplayDraft($0)) },
                            onShow: { selectedId = $0 },
                            // Only the open detail shows the links, so only its are worked out.
                            links: isSelected ? NetworkReplayLinks(of: entry, in: store.entries) : .none,
                            replayStatus: replays.statuses[entry.id]
                        )
                    }
                }

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
            }
        }
    }

    /// The totals above the request list: how many requests, the share of completed ones that
    /// succeeded (2xx) and their mean duration.
    struct NetworkStats: Equatable {
        var total: Int
        var successRate: String
        var averageTime: String

        init(_ entries: [NetworkEntry]) {
            total = entries.count
            let completed = entries.filter(\.isComplete)
            let successes = completed.filter { (200 ..< 300).contains($0.statusCode ?? 0) }
            successRate = completed.isEmpty
                ? "—" : String(format: "%.0f%%", Double(successes.count) / Double(completed.count) * 100)
            let durations = completed.compactMap(\.duration)
            if durations.isEmpty {
                averageTime = "—"
            } else {
                let mean = durations.reduce(0, +) / Double(durations.count)
                averageTime = mean < 1 ? String(format: "%.0fms", mean * 1000) : String(format: "%.2fs", mean)
            }
        }
    }

    /// A request's method, status, path and duration, after an error glyph when it failed;
    /// selected, it shows the request's detail.
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
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                Button(action: onSelect) {
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
                    .debugDrawerRowPadding()
                    .contentShape(Rectangle())
                }
                .debugDrawerButtonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])

                if isSelected {
                    NetworkRequestDetail(
                        entry: entry, redaction: redaction, onMock: onMock, onResend: onResend, onEditAndResend: onEditAndResend,
                        onShow: onShow, links: links, replayStatus: replayStatus
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
