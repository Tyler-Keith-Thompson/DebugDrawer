#if DEBUG
    import DebugDrawer
    import SwiftUI

    struct DiskIOPluginView: View {
        @ObservedObject private var store = DiskIOStore.shared

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                DebugDrawerSection("Totals") {
                    DebugDrawerKeyValueRow("Reads", value: "\(store.totalReads)")
                    DebugDrawerKeyValueRow("Writes", value: "\(store.totalWrites)")
                    DebugDrawerKeyValueRow("Read", value: store.totalBytesRead.byteLabel)
                    DebugDrawerKeyValueRow("Written", value: store.totalBytesWritten.byteLabel)
                    if store.mainThreadOps > 0 {
                        DebugDrawerIssueRow("Main thread", status: "\(store.mainThreadOps) calls", severity: .warning)
                    }
                }

                DebugDrawerSection("Calls") {
                    DebugDrawerRow("Operation") {
                        Picker("Operation", selection: $store.filterOp) {
                            Text("All").tag(IOEvent.Operation?.none)
                            ForEach([IOEvent.Operation.read, .write, .delete, .list], id: \.rawValue) { operation in
                                Text(operation.name).tag(IOEvent.Operation?.some(operation))
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    DebugDrawerRow("Main thread only", isOn: $store.mainThreadOnly)
                    // With nothing to list, a sentence says why rather than an empty well.
                    if store.filteredEvents.isEmpty {
                        Text(store.events.isEmpty ? "No calls yet." : "No calls match the filter.")
                            .debugDrawerFont(.secondary)
                            .debugDrawerForegroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .debugDrawerRowPadding()
                    } else {
                        DebugDrawerCodeBlock {
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 0) {
                                    ForEach(store.filteredEvents) { event in
                                        IOEventRow(event: event)
                                    }
                                }
                            }
                            .frame(maxHeight: 250)
                        }
                    }
                }

                DiskSpaceRows(volume: DiskSpace.home)

                DebugDrawerActionRow {
                    EmptyView()
                } trailing: {
                    Button("Clear", role: .destructive) { store.clear() }
                        .debugDrawerButtonStyle(.destructive)
                        .accessibilityLabel("Clear recorded calls")
                }
            }
        }
    }

    /// The home volume's size and free space, read when the plugin draws.
    struct DiskSpace: Equatable {
        let total: Int64
        let free: Int64

        /// The volume holding the home directory, or `nil` when the system won't say.
        static var home: DiskSpace? {
            guard let attributes = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
                  let total = attributes[.systemSize] as? Int64,
                  let free = attributes[.systemFreeSize] as? Int64,
                  total > 0 else { return nil }
            return DiskSpace(total: total, free: free)
        }
    }

    /// How full the volume is, as a gauge, and its free space.
    struct DiskSpaceRows: View {
        let volume: DiskSpace?

        var body: some View {
            if let volume {
                let used = Double(volume.total - volume.free) / Double(volume.total)
                DebugDrawerSection("Disk") {
                    DebugDrawerGaugeRow(
                        "Used",
                        value: "\(Int((used * 100).rounded()))%",
                        fraction: used,
                        severity: used >= 0.9 ? .warning : nil
                    )
                    DebugDrawerKeyValueRow("Free", value: volume.free.byteLabel)
                }
            }
        }
    }

    /// One recorded I/O call: its operation, a warning when it ran on the main thread, the path's
    /// last components, its size (or item count for a listing) and how long it took.
    struct IOEventRow: View {
        let event: IOEvent
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        @ScaledMetric(relativeTo: .body) private var badgeWidth = 14

        var body: some View {
            VStack(spacing: 0) {
                Group {
                    // At accessibility text sizes the path and the measurements have no room beside
                    // the badge, so each takes a line of its own.
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: 6) {
                                operationBadge
                                mainThreadWarning
                            }
                            path
                            measurements
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        HStack(spacing: 6) {
                            operationBadge
                            mainThreadWarning
                            path
                            Spacer()
                            measurements
                        }
                    }
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)

                Divider()
            }
        }

        private var operationBadge: some View {
            Text(event.operation.rawValue)
                .debugDrawerFont(.code)
                .fontWeight(.bold)
                .debugDrawerForegroundStyle(.secondary)
                .frame(width: badgeWidth)
                .accessibilityLabel(event.operation.name)
        }

        @ViewBuilder private var mainThreadWarning: some View {
            if event.isMainThread {
                DebugDrawerIssueGlyph(.warning)
                    .accessibilityLabel("On the main thread")
            }
        }

        // The last two components.
        private var path: some View {
            Text(event.shortPath)
                .debugDrawerFont(.code)
                .lineLimit(3)
                .truncationMode(.head)
        }

        // The size (or item count for a listing), then the duration; a slow call's duration in
        // the primary color, so it stands out from the tertiary ones.
        @ViewBuilder private var measurements: some View {
            Group {
                if event.size > 0 && event.operation != .list {
                    Text(event.size.byteLabel)
                        .debugDrawerForegroundStyle(.tertiary)
                }
                if event.operation == .list {
                    Text("\(event.size) items")
                        .debugDrawerForegroundStyle(.tertiary)
                }
                Text(event.durationLabel)
                    .debugDrawerForegroundStyle(event.duration > 0.01 ? .primary : .tertiary)
            }
            .debugDrawerFont(.value)
        }
    }

    extension IOEvent {
        /// The path, or its last two components after `.../` when it is longer than three.
        fileprivate var shortPath: String {
            let components = (path as NSString).pathComponents
            if components.count <= 3 { return path }
            return ".../" + components.suffix(2).joined(separator: "/")
        }

        fileprivate var durationLabel: String {
            if duration < 0.001 { return "<1 ms" }
            if duration < 1 { return String(format: "%.0f ms", duration * 1000) }
            return String(format: "%.2f s", duration)
        }
    }

    extension Int64 {
        /// A byte count in B, KB, MB or GB, the figure and unit apart ("1.5 MB").
        fileprivate var byteLabel: String {
            if self < 1024 { return "\(self) B" }
            if self < 1024 * 1024 { return "\(self / 1024) KB" }
            if self < 1024 * 1024 * 1024 { return String(format: "%.1f MB", Double(self) / (1024 * 1024)) }
            return String(format: "%.1f GB", Double(self) / (1024 * 1024 * 1024))
        }
    }
#endif
