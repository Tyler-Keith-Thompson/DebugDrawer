#if DEBUG
    import DebugDrawer
    import SwiftUI

    struct NetworkPluginView: View {
        @ObservedObject private var store = NetworkStore.shared
        @ObservedObject private var drawer = DebugDrawer.shared
        @State private var selectedId: UUID?

        var body: some View {
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
                        NetworkRequestRow(entry: entry, redaction: drawer.redaction, isSelected: selectedId == entry.id) {
                            selectedId = selectedId == entry.id ? nil : entry.id
                        }
                    }
                }
            }
        }
    }

    /// The Network plugin's header accessory, read from the shared store as the plugin's body
    /// reads it.
    struct NetworkHeaderAccessoryView: View {
        @ObservedObject private var store = NetworkStore.shared

        var body: some View {
            NetworkHeaderSummary(entries: store.entries)
        }
    }

    /// How many requests the plugin holds ("38 requests"), and an error glyph with the count of
    /// those that failed, when any did.
    struct NetworkHeaderSummary: View {
        let total: Int
        let failures: Int

        init(entries: [NetworkEntry]) {
            total = entries.count
            failures = entries.count(where: \.isFailure)
        }

        var body: some View {
            HStack {
                if failures > 0 {
                    DebugDrawerIssueCount(.error, count: failures)
                }
                Text(total == 1 ? "1 request" : "\(total.formatted()) requests")
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
                        HStack(alignment: .firstTextBaseline) {
                            glyph
                            Text(entry.method)
                                .debugDrawerFont(.code)
                                .debugDrawerForegroundStyle(.secondary)
                            status
                        }
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
                    NetworkRequestDetail(entry: entry, redaction: redaction)
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
    struct NetworkRequestDetail: View {
        let entry: NetworkEntry
        let redaction: DebugDrawerRedaction

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
