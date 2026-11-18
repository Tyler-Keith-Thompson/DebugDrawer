#if DEBUG
    import DebugDrawer
    import SwiftUI

    struct DiskIOPluginView: View {
        @ObservedObject private var store = DiskIOStore.shared
        /// The home volume, sampled off the main actor when the plugin appears and on Refresh;
        /// `nil` until the first sample.
        @State private var diskSpace: DiskSpace?
        /// Bumped by Refresh, which samples the volume again.
        @State private var diskSpaceRequest = 0

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                DiskIOTotalsRows(totals: store.totals)

                DebugDrawerSection("Calls") {
                    DebugDrawerRow("Operation") {
                        Picker("Operation", selection: $store.filterOp) {
                            Text("All").tag(IOEvent.Operation?.none)
                            ForEach(IOEvent.Operation.filterable, id: \.rawValue) { operation in
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

                DiskSpaceRows(volume: diskSpace)

                DebugDrawerActionRow {
                    Button("Refresh") { diskSpaceRequest += 1 }
                        .accessibilityLabel("Refresh disk space")
                } trailing: {
                    Button("Clear", role: .destructive) { store.clear() }
                        .debugDrawerButtonStyle(.destructive)
                        .accessibilityLabel("Clear recorded calls")
                }
            }
            .task(id: diskSpaceRequest) {
                diskSpace = await DiskSpace.sample()
            }
        }
    }

    extension IOEvent.Operation {
        /// The operations the filter offers, in the order it lists them.
        fileprivate static let filterable: [Self] = [.read, .write, .create, .delete, .list, .stat, .copy, .move]
    }

    /// The counts of every recorded call: reads and writes, the bytes of each, and a warning for
    /// calls on the main thread and an error for calls that failed.
    struct DiskIOTotalsRows: View {
        let totals: DiskIOTotals

        var body: some View {
            DebugDrawerSection("Totals") {
                DebugDrawerKeyValueRow("Reads", value: "\(totals.reads)")
                DebugDrawerKeyValueRow("Writes", value: "\(totals.writes)")
                DebugDrawerKeyValueRow("Read", value: totals.bytesRead.byteLabel)
                DebugDrawerKeyValueRow("Written", value: totals.bytesWritten.byteLabel)
                if totals.mainThreadCalls > 0 {
                    DebugDrawerIssueRow("Main thread", status: totals.mainThreadCalls.callsLabel, severity: .warning)
                }
                if totals.failures > 0 {
                    DebugDrawerIssueRow("Failed", status: totals.failures.callsLabel, severity: .error)
                }
            }
        }
    }

    /// How full the volume is, as a gauge, and its free space; nothing when `volume` is `nil`.
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

    /// One recorded I/O call: its operation, a warning when it ran on the main thread, an error
    /// when it failed, the path's last components (and a copy's or move's destination), its size
    /// (or item count for a listing) and how long it took, then the error's description.
    struct IOEventRow: View {
        let event: IOEvent
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        // Wide enough for the two-letter badges (Cp, Mv).
        @ScaledMetric(relativeTo: .body) private var badgeWidth = 20

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                Group {
                    // At accessibility text sizes the path and the measurements have no room beside
                    // the badge, so each takes a line of its own.
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: 6) {
                                operationBadge
                                glyphs
                            }
                            path
                            measurements
                            failure
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: 6) {
                                operationBadge
                                glyphs
                                path
                                Spacer()
                                measurements
                            }
                            failure
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
                .frame(width: badgeWidth, alignment: .leading)
                .accessibilityLabel(event.operation.name)
        }

        @ViewBuilder private var glyphs: some View {
            if event.isMainThread {
                DebugDrawerIssueGlyph(.warning)
                    .accessibilityLabel("On the main thread")
            }
            if event.error != nil {
                DebugDrawerIssueGlyph(.error)
                    .accessibilityLabel("Failed")
            }
        }

        // The last two components, and a copy's or move's destination's name after an arrow.
        private var path: some View {
            Text(event.destination.map { "\(event.shortPath) → \(($0 as NSString).lastPathComponent)" } ?? event.shortPath)
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
                if event.operation == .list && event.error == nil {
                    Text("\(event.size) items")
                        .debugDrawerForegroundStyle(.tertiary)
                }
                Text(event.durationLabel)
                    .debugDrawerForegroundStyle(event.duration > 0.01 ? .primary : .tertiary)
            }
            .debugDrawerFont(.value)
        }

        @ViewBuilder private var failure: some View {
            if let error = event.error {
                Text(error.localizedDescription)
                    .debugDrawerFont(.secondary)
                    .debugDrawerForegroundStyle(.error)
                    .lineLimit(3)
                    .padding(.leading, dynamicTypeSize.isAccessibilitySize ? 0 : badgeWidth + 6)
            }
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

    extension Int {
        /// "1 call", "3 calls".
        fileprivate var callsLabel: String {
            self == 1 ? "1 call" : "\(self) calls"
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
