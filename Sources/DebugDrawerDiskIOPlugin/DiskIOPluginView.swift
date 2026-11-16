#if DEBUG
    import DebugDrawer
    import SwiftUI

    struct DiskIOPluginView: View {
        @ObservedObject private var store = DiskIOStore.shared

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                // Stats bar
                HStack(spacing: 10) {
                    DebugDrawerStatBadge("R", value: "\(store.totalReads)", color: .blue)
                    DebugDrawerStatBadge("W", value: "\(store.totalWrites)", color: .orange)
                    DebugDrawerStatBadge("Read", value: store.totalBytesRead.byteLabel, color: .blue)
                    DebugDrawerStatBadge("Written", value: store.totalBytesWritten.byteLabel, color: .orange)

                    Spacer()

                    if store.mainThreadOps > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundStyle(.red)
                                .accessibilityHidden(true)
                            Text("\(store.mainThreadOps) main")
                                .font(.system(.caption2, weight: .bold))
                                .foregroundStyle(.red)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(store.mainThreadOps) on the main thread")
                    }
                }

                // Filters
                HStack(spacing: 4) {
                    filterButton("All", isActive: store.filterOp == nil && !store.mainThreadOnly) {
                        store.filterOp = nil
                        store.mainThreadOnly = false
                    }

                    ForEach([IOEvent.Operation.read, .write, .delete, .list], id: \.rawValue) { op in
                        filterButton(op.rawValue, color: op.color, isActive: store.filterOp == op) {
                            store.filterOp = store.filterOp == op ? nil : op
                        }
                    }

                    Spacer()

                    Toggle("Main", isOn: $store.mainThreadOnly)
                        .toggleStyle(.switch)
                        .controlSize(.mini)

                    Button("Clear") { store.clear() }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }

                // Event list
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(store.filteredEvents) { event in
                            IOEventRow(event: event)
                        }
                    }
                }
                .frame(maxHeight: 250)
                .background(Color.black.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 4))

                // Disk space
                diskSpaceRow
            }
        }

        private func filterButton(_ label: String, color: Color = .secondary, isActive: Bool, action: @escaping () -> Void) -> some View {
            Button(action: action) {
                Text(label)
                    .font(.system(.caption2, design: .monospaced, weight: isActive ? .bold : .regular))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(isActive ? color.opacity(0.2) : Color.clear)
                    .cornerRadius(3)
            }
            .buttonStyle(.plain)
        }

        private var diskSpaceRow: some View {
            HStack {
                if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
                   let total = attrs[.systemSize] as? Int64,
                   let free = attrs[.systemFreeSize] as? Int64 {
                    let used = total - free
                    let pct = Double(used) / Double(total)

                    Text("Disk:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ProgressView(value: pct)
                        .controlSize(.small)
                        .frame(width: 80)

                    Text("\(free.byteLabel) free")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }

    /// One recorded I/O call: its operation, a warning when it ran on the main thread, the path's
    /// last components, its size (or item count for a listing) and how long it took.
    struct IOEventRow: View {
        let event: IOEvent
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        @ScaledMetric(relativeTo: .caption2) private var badgeWidth = 14

        var body: some View {
            VStack(spacing: 0) {
                Group {
                    // At accessibility text sizes the path has no room beside the size and
                    // duration, so it takes a line of its own.
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: 6) {
                                operationBadge
                                mainThreadWarning
                                Spacer()
                                measurements
                            }
                            path
                        }
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
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)

                Divider().padding(.leading, 24)
            }
        }

        private var operationBadge: some View {
            Text(event.operation.rawValue)
                .font(.system(.caption2, design: .monospaced, weight: .bold))
                .frame(width: badgeWidth)
                .foregroundStyle(event.operation.color)
        }

        @ViewBuilder private var mainThreadWarning: some View {
            if event.isMainThread {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .accessibilityLabel("On the main thread")
            }
        }

        // The last two components.
        private var path: some View {
            Text(event.shortPath)
                .font(.system(.caption2, design: .monospaced))
                .lineLimit(3)
                .truncationMode(.head)
        }

        // The size (or item count for a listing), then the duration.
        @ViewBuilder private var measurements: some View {
            if event.size > 0 && event.operation != .list {
                Text(event.size.byteLabel)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            if event.operation == .list {
                Text("\(event.size) items")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Text(event.durationLabel)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(event.duration > 0.01 ? Color.orange : Color.secondary)
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
            if duration < 0.001 { return "<1ms" }
            if duration < 1 { return String(format: "%.0fms", duration * 1000) }
            return String(format: "%.2fs", duration)
        }
    }

    extension Int64 {
        /// A byte count in B, KB or MB.
        fileprivate var byteLabel: String {
            if self < 1024 { return "\(self)B" }
            if self < 1024 * 1024 { return "\(self / 1024)KB" }
            return String(format: "%.1fMB", Double(self) / (1024 * 1024))
        }
    }
#endif
