#if DEBUG
    import DebugDrawer
    import SwiftUI

    struct NetworkPluginView: View {
        @ObservedObject private var store = NetworkStore.shared
        @ObservedObject private var drawer = DebugDrawer.shared
        @State private var selectedId: UUID?

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                // Stats summary
                if !store.entries.isEmpty {
                    let stats = NetworkStats(store.entries)
                    HStack(spacing: 12) {
                        DebugDrawerStatBadge("Total", value: "\(stats.total)")
                        DebugDrawerStatBadge("Success", value: stats.successRate)
                        DebugDrawerStatBadge("Avg Time", value: stats.averageTime)
                    }
                    .padding(.vertical, 2)
                }

                NetworkToolbar(count: store.filteredEntries.count, filterStatus: $store.filterStatus) { store.clear() }

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

    /// A request's method, status, path and duration; selected, it shows the request's detail.
    struct NetworkRequestRow: View {
        let entry: NetworkEntry
        let redaction: DebugDrawerRedaction
        let isSelected: Bool
        let onSelect: () -> Void
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                Button(action: onSelect) {
                    Group {
                        // At accessibility text sizes the path has no room beside the method,
                        // status and duration, so it takes a line of its own.
                        if dynamicTypeSize.isAccessibilitySize {
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 6) {
                                    methodBadge
                                    status
                                    Spacer()
                                    duration
                                }
                                path
                            }
                        } else {
                            HStack(spacing: 6) {
                                methodBadge
                                status
                                path
                                Spacer()
                                duration
                            }
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])

                if isSelected {
                    NetworkRequestDetail(entry: entry, redaction: redaction)
                        .padding(.horizontal, 6)
                        .padding(.bottom, 6)
                }

                Divider().padding(.leading, 6)
            }
        }

        private var methodBadge: some View {
            Text(entry.method)
                .font(.system(.caption2, design: .monospaced, weight: .bold))
                .padding(.horizontal, 3)
                .background(methodColor(entry.method).opacity(0.15))
                .cornerRadius(2)
        }

        @ViewBuilder private var status: some View {
            if let code = entry.statusCode {
                Text("\(code)")
                    .font(.system(.caption2, design: .monospaced, weight: .bold))
                    .foregroundStyle(entry.statusColor)
            } else if !entry.isComplete {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Text("ERR")
                    .font(.system(.caption2, design: .monospaced, weight: .bold))
                    .foregroundStyle(.red)
            }
        }

        private var path: some View {
            Text(entry.path)
                .font(.system(.caption2, design: .monospaced))
                .lineLimit(3)
                .truncationMode(.middle)
        }

        private var duration: some View {
            Text(entry.durationLabel)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)
        }

        private func methodColor(_ method: String) -> Color {
            switch method {
            case "GET": .blue
            case "POST": .green
            case "PUT", "PATCH": .orange
            case "DELETE": .red
            default: .secondary
            }
        }
    }

    /// A request in full: its URL, time, size and status, query parameters, timing, error, headers
    /// and bodies, with a button to copy it as a cURL command. Values the redaction rules call
    /// sensitive are masked in the copy, and on screen until revealed.
    struct NetworkRequestDetail: View {
        let entry: NetworkEntry
        let redaction: DebugDrawerRedaction
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                // URL
                RedactedText(entry.url, redacted: redaction.redacting(url: entry.url))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)

                // Timing + size + actions. At accessibility text sizes the badges and the button
                // don't fit one line, so the button goes below the badges.
                let summaryLayout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                    : AnyLayout(HStackLayout(spacing: 12))
                summaryLayout {
                    HStack(spacing: 12) {
                        DebugDrawerStatBadge("Time", value: entry.durationLabel)
                        DebugDrawerStatBadge("Size", value: entry.responseSizeLabel)
                        if let code = entry.statusCode {
                            DebugDrawerStatBadge("Status", value: "\(code)")
                        }
                    }

                    if !dynamicTypeSize.isAccessibilitySize {
                        Spacer()
                    }

                    DebugDrawerCopyButton("Copy cURL") { entry.curl(redaction: redaction) }
                }

                // URL query parameters
                if let urlObj = URL(string: entry.url),
                   let components = URLComponents(url: urlObj, resolvingAgainstBaseURL: false),
                   let queryItems = components.queryItems, !queryItems.isEmpty {
                    collapsibleSection("Query Parameters") {
                        VStack(alignment: .leading, spacing: 1) {
                            ForEach(queryItems, id: \.name) { item in
                                HStack(alignment: .top, spacing: 4) {
                                    Text(item.name + ":")
                                        .font(.system(.caption2, design: .monospaced, weight: .medium))
                                        .foregroundStyle(.secondary)
                                    RedactedText(
                                        item.value ?? "",
                                        redacted: redaction.redacting(item.value ?? "", forKey: item.name)
                                    )
                                    .font(.system(.caption2, design: .monospaced))
                                }
                            }
                        }
                        .padding(4)
                    }
                }

                if let metrics = entry.metrics {
                    collapsibleSection("Timing") {
                        NetworkTimingView(metrics: metrics)
                    }
                }

                if let error = entry.error {
                    Text(error)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.red)
                        .padding(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(3)
                }

                payload
            }
        }

        @ViewBuilder
        private var payload: some View {
            // Request headers
            if !entry.requestHeaders.isEmpty {
                collapsibleSection("Request Headers") {
                    headersView(entry.requestHeaders)
                }
            }

            // Request body
            if let body = entry.requestBody, let pretty = body.prettyBody {
                collapsibleSection("Request Body") {
                    codeBlock(pretty, redacted: redaction.redacting(json: body).prettyBody ?? pretty)
                }
            }

            // Response headers
            if let headers = entry.responseHeaders, !headers.isEmpty {
                collapsibleSection("Response Headers") {
                    headersView(headers)
                }
            }

            // Response body
            if let body = entry.responseBody, let pretty = body.prettyBody {
                collapsibleSection("Response Body") {
                    codeBlock(pretty, redacted: redaction.redacting(json: body).prettyBody ?? pretty)
                }
            }
        }

        private func collapsibleSection(_ title: String, @ViewBuilder content: @escaping () -> some View) -> some View {
            DisclosureGroup(title) {
                content()
            }
            .font(.caption)
        }

        private func headersView(_ headers: [String: String]) -> some View {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(headers.keys.sorted(), id: \.self) { key in
                    HStack(alignment: .top, spacing: 4) {
                        Text(key + ":")
                            .font(.system(.caption2, design: .monospaced, weight: .medium))
                            .foregroundStyle(.secondary)
                        let value = headers[key] ?? ""
                        RedactedText(value, redacted: redaction.masksHeader(key) ? DebugDrawerRedaction.mask : value)
                            .font(.system(.caption2, design: .monospaced))
                    }
                }
            }
            .padding(4)
        }

        private func codeBlock(_ text: String, redacted: String) -> some View {
            ScrollView(.horizontal) {
                RedactedText(text, redacted: redacted)
                    .font(.system(.caption2, design: .monospaced))
                    .padding(4)
            }
            .frame(maxHeight: 150)
            .background(Color.primary.opacity(0.05))
            .cornerRadius(3)
        }
    }
#endif
