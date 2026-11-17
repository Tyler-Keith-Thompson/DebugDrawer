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
        }

        @ObservedObject private var store = NetworkStore.shared
        @ObservedObject private var mocks = NetworkMocksModel.shared
        @ObservedObject private var conditions = NetworkConditionsModel.shared
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
                        NetworkRequestRow(
                            entry: entry, redaction: drawer.redaction, isSelected: selectedId == entry.id,
                            onSelect: { selectedId = selectedId == entry.id ? nil : entry.id },
                            onMock: { screen = .mock(NetworkMockDraft(mocks.rule(mocking: $0), isNew: true)) }
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
                            if badgesOnOwnLine, entry.mockRuleName != nil || entry.conditionEffect != nil {
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
                    NetworkRequestDetail(entry: entry, redaction: redaction, onMock: onMock)
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
        /// would squeeze the status, and when both show, since two beside the method and status
        /// leave the path a letter's width in a phone-wide drawer.
        private var badgesOnOwnLine: Bool {
            dynamicTypeSize.isAccessibilitySize || (entry.mockRuleName != nil && entry.conditionEffect != nil)
        }

        /// Mocked and Conditioned, for a request a mock answered or a profile conditioned.
        @ViewBuilder private var badges: some View {
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

    /// A request in full: its URL, time, size and status, query parameters, timing, error, headers
    /// and bodies, with a button to copy it as a cURL command. Values the redaction rules call
    /// sensitive are masked in the copy, and on screen until revealed.
    ///
    /// A request a mock answered names the mock; any other offers Mock This once it is complete.
    struct NetworkRequestDetail: View {
        let entry: NetworkEntry
        let redaction: DebugDrawerRedaction
        /// Opens a new mock made from the request; `nil` offers no Mock This.
        var onMock: ((NetworkEntry) -> Void)?

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                RedactedText(entry.url, redacted: redaction.redacting(url: entry.url))
                    .debugDrawerFont(.code)
                    .debugDrawerForegroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                DebugDrawerKeyValueRow("Time", value: entry.durationLabel)
                DebugDrawerKeyValueRow("Size", value: entry.responseSizeLabel)
                if let code = entry.statusCode {
                    DebugDrawerKeyValueRow("Status", value: String(code))
                }
                if let rule = entry.mockRuleName {
                    DebugDrawerKeyValueRow("Mocked by", value: rule)
                        .debugDrawerValueStyle(.text)
                }
                if let effect = entry.conditionEffect {
                    DebugDrawerKeyValueRow("Conditioned by", value: effect.profileName)
                        .debugDrawerValueStyle(.text)
                    DebugDrawerKeyValueRow("Condition", value: effect.summary)
                        .debugDrawerValueStyle(.text)
                }

                if let error = entry.error {
                    DebugDrawerIssueRow("Request failed", severity: .error) {
                        Text(error)
                    }
                }

                // URL query parameters
                if let urlObj = URL(string: entry.url),
                   let components = URLComponents(url: urlObj, resolvingAgainstBaseURL: false),
                   let queryItems = components.queryItems, !queryItems.isEmpty {
                    collapsibleSection("Query Parameters") {
                        ForEach(queryItems, id: \.name) { item in
                            DebugDrawerKeyValueRow(
                                item.name,
                                value: item.value ?? "",
                                redacted: redaction.redacting(item.value ?? "", forKey: item.name)
                            )
                        }
                        .debugDrawerValueStyle(.code)
                    }
                }

                if let metrics = entry.metrics {
                    collapsibleSection("Timing") {
                        NetworkTimingView(metrics: metrics)
                    }
                }

                payload

                DebugDrawerActionRow {
                    DebugDrawerCopyButton("Copy cURL") { entry.curl(redaction: redaction) }
                    if let onMock, entry.isComplete, entry.mockRuleName == nil {
                        Button("Mock This") { onMock(entry) }
                            .accessibilityLabel("Mock This")
                            .accessibilityHint("Makes a mock that answers requests like this one with its response")
                    }
                }
            }
        }

        @ViewBuilder
        private var payload: some View {
            if !entry.requestHeaders.isEmpty {
                collapsibleSection("Request Headers") {
                    headersView(entry.requestHeaders)
                }
            }

            if let body = entry.requestBody, let pretty = body.prettyBody {
                collapsibleSection("Request Body") {
                    codeBlock(pretty, redacted: redaction.redacting(json: body).prettyBody ?? pretty)
                }
            }

            if let headers = entry.responseHeaders, !headers.isEmpty {
                collapsibleSection("Response Headers") {
                    headersView(headers)
                }
            }

            if let body = entry.responseBody, let pretty = body.prettyBody {
                collapsibleSection("Response Body") {
                    codeBlock(pretty, redacted: redaction.redacting(json: body).prettyBody ?? pretty)
                }
            }
        }

        private func collapsibleSection(_ title: String, @ViewBuilder content: @escaping () -> some View) -> some View {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 0) {
                    content()
                }
            } label: {
                Text(title)
                    .debugDrawerFont(.heading)
            }
        }

        @ViewBuilder
        private func headersView(_ headers: [String: String]) -> some View {
            ForEach(headers.keys.sorted(), id: \.self) { key in
                let value = headers[key] ?? ""
                DebugDrawerKeyValueRow(key, value: value, redacted: redaction.masksHeader(key) ? DebugDrawerRedaction.mask : value)
            }
            // A header's value is code even when it is a word ("gzip", "close").
            .debugDrawerValueStyle(.code)
        }

        private func codeBlock(_ text: String, redacted: String) -> some View {
            DebugDrawerCodeBlock {
                RedactedText(text, redacted: redacted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
#endif
