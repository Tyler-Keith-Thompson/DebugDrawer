#if DEBUG
    import Combine
    import DebugDrawer
    import Foundation
    import ObjectiveC
    import SwiftUI

    // MARK: - I/O event model

    public struct IOEvent: Identifiable {
        public let id = UUID()
        public let timestamp: Date
        public let operation: Operation
        public let path: String
        public let size: Int64
        public let duration: TimeInterval
        public let isMainThread: Bool

        public enum Operation: String {
            case read = "R"
            case write = "W"
            case delete = "D"
            case create = "C"
            case list = "L"
            case stat = "S"

            var color: Color {
                switch self {
                case .read: .blue
                case .write: .orange
                case .delete: .red
                case .create: .green
                case .list: .purple
                case .stat: .secondary
                }
            }
        }
    }

    // MARK: - I/O monitor store

    @MainActor
    public final class DiskIOStore: ObservableObject {
        public static let shared = DiskIOStore()

        @Published public private(set) var events: [IOEvent] = []
        @Published public var filterOp: IOEvent.Operation?
        @Published public var mainThreadOnly = false

        public var capacity = 500
        private var installed = false
        private let lineSubject = PassthroughSubject<IOEvent, Never>()
        private var cancellable: AnyCancellable?

        /// Stats
        public var totalReads: Int {
            events.filter { $0.operation == .read }.count
        }

        public var totalWrites: Int {
            events.filter { $0.operation == .write }.count
        }

        public var totalBytesRead: Int64 {
            events.filter { $0.operation == .read }.reduce(0) { $0 + $1.size }
        }

        public var totalBytesWritten: Int64 {
            events.filter { $0.operation == .write }.reduce(0) { $0 + $1.size }
        }

        public var mainThreadOps: Int {
            events.filter(\.isMainThread).count
        }

        public var filteredEvents: [IOEvent] {
            var result = events
            if let op = filterOp { result = result.filter { $0.operation == op } }
            if mainThreadOnly { result = result.filter(\.isMainThread) }
            return result
        }

        private init() {
            cancellable = lineSubject
                .collect(.byTime(DispatchQueue.main, .milliseconds(200)))
                .receive(on: DispatchQueue.main)
                .sink { [weak self] batch in
                    guard let self, !batch.isEmpty else { return }
                    self.events.insert(contentsOf: batch, at: 0)
                    if self.events.count > self.capacity {
                        self.events.removeLast(self.events.count - self.capacity)
                    }
                }
        }

        public func install() {
            guard !installed else { return }
            installed = true
            DiskIOSwizzler.install()
        }

        func record(_ event: IOEvent) {
            lineSubject.send(event)
        }

        public func clear() {
            events.removeAll()
        }
    }

    // MARK: - FileManager swizzling

    enum DiskIOSwizzler {
        static func install() {
            // Swizzle contentsOfFile (read)
            swizzle(
                cls: FileManager.self,
                original: #selector(FileManager.contents(atPath:)),
                swizzled: #selector(FileManager.dd_contents(atPath:))
            )

            // Swizzle createFile (write)
            swizzle(
                cls: FileManager.self,
                original: #selector(FileManager.createFile(atPath:contents:attributes:)),
                swizzled: #selector(FileManager.dd_createFile(atPath:contents:attributes:))
            )

            // Swizzle removeItem (delete)
            swizzle(
                cls: FileManager.self,
                original: #selector(FileManager.removeItem(atPath:)),
                swizzled: #selector(FileManager.dd_removeItem(atPath:))
            )

            // Swizzle contentsOfDirectory (list)
            swizzle(
                cls: FileManager.self,
                original: #selector(FileManager.contentsOfDirectory(atPath:)),
                swizzled: #selector(FileManager.dd_contentsOfDirectory(atPath:))
            )

            // Swizzle attributesOfItem (stat)
            swizzle(
                cls: FileManager.self,
                original: #selector(FileManager.attributesOfItem(atPath:)),
                swizzled: #selector(FileManager.dd_attributesOfItem(atPath:))
            )
        }

        private static func swizzle(cls: AnyClass, original: Selector, swizzled: Selector) {
            guard let originalMethod = class_getInstanceMethod(cls, original),
                  let swizzledMethod = class_getInstanceMethod(cls, swizzled)
            else { return }
            method_exchangeImplementations(originalMethod, swizzledMethod)
        }
    }

    // MARK: - Swizzled FileManager methods

    extension FileManager {
        @objc func dd_contents(atPath path: String) -> Data? {
            let start = CFAbsoluteTimeGetCurrent()
            let result = dd_contents(atPath: path) // calls original
            let duration = CFAbsoluteTimeGetCurrent() - start
            let size = Int64(result?.count ?? 0)

            let event = IOEvent(
                timestamp: Date(), operation: .read, path: path,
                size: size, duration: duration, isMainThread: Thread.isMainThread
            )
            Task { @MainActor in DiskIOStore.shared.record(event) }
            return result
        }

        @objc func dd_createFile(atPath path: String, contents data: Data?, attributes: [FileAttributeKey: Any]?) -> Bool {
            let start = CFAbsoluteTimeGetCurrent()
            let result = dd_createFile(atPath: path, contents: data, attributes: attributes)
            let duration = CFAbsoluteTimeGetCurrent() - start

            let event = IOEvent(
                timestamp: Date(), operation: .write, path: path,
                size: Int64(data?.count ?? 0), duration: duration, isMainThread: Thread.isMainThread
            )
            Task { @MainActor in DiskIOStore.shared.record(event) }
            return result
        }

        @objc func dd_removeItem(atPath path: String) throws {
            let start = CFAbsoluteTimeGetCurrent()
            try dd_removeItem(atPath: path)
            let duration = CFAbsoluteTimeGetCurrent() - start

            let event = IOEvent(
                timestamp: Date(), operation: .delete, path: path,
                size: 0, duration: duration, isMainThread: Thread.isMainThread
            )
            Task { @MainActor in DiskIOStore.shared.record(event) }
        }

        @objc func dd_contentsOfDirectory(atPath path: String) throws -> [String] {
            let start = CFAbsoluteTimeGetCurrent()
            let result = try dd_contentsOfDirectory(atPath: path)
            let duration = CFAbsoluteTimeGetCurrent() - start

            let event = IOEvent(
                timestamp: Date(), operation: .list, path: path,
                size: Int64(result.count), duration: duration, isMainThread: Thread.isMainThread
            )
            Task { @MainActor in DiskIOStore.shared.record(event) }
            return result
        }

        @objc func dd_attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any] {
            let start = CFAbsoluteTimeGetCurrent()
            let result = try dd_attributesOfItem(atPath: path)
            let duration = CFAbsoluteTimeGetCurrent() - start

            let event = IOEvent(
                timestamp: Date(), operation: .stat, path: path,
                size: (result[.size] as? Int64) ?? 0, duration: duration, isMainThread: Thread.isMainThread
            )
            Task { @MainActor in DiskIOStore.shared.record(event) }
            return result
        }
    }

    // MARK: - Plugin

    public struct DiskIOPlugin: DebugDrawerPlugin {
        public var title = "Disk I/O"
        public var icon = "externaldrive"

        public init() {}

        public var body: some View {
            DiskIOPluginView()
        }
    }

    struct DiskIOPluginView: View {
        @ObservedObject private var store = DiskIOStore.shared

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                // Stats bar
                HStack(spacing: 10) {
                    statBadge("R", value: "\(store.totalReads)", color: .blue)
                    statBadge("W", value: "\(store.totalWrites)", color: .orange)
                    statBadge("Read", value: formatBytes(store.totalBytesRead), color: .blue)
                    statBadge("Written", value: formatBytes(store.totalBytesWritten), color: .orange)

                    Spacer()

                    if store.mainThreadOps > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.red)
                            Text("\(store.mainThreadOps) main")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.red)
                        }
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
                            eventRow(event)
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

        private func statBadge(_ label: String, value: String, color: Color) -> some View {
            VStack(spacing: 0) {
                Text(value)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)
                Text(label)
                    .font(.system(size: 7))
                    .foregroundStyle(.tertiary)
            }
        }

        private func filterButton(_ label: String, color: Color = .secondary, isActive: Bool, action: @escaping () -> Void) -> some View {
            Button(action: action) {
                Text(label)
                    .font(.system(size: 9, weight: isActive ? .bold : .regular, design: .monospaced))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(isActive ? color.opacity(0.2) : Color.clear)
                    .cornerRadius(3)
            }
            .buttonStyle(.plain)
        }

        private func eventRow(_ event: IOEvent) -> some View {
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    // Operation badge
                    Text(event.operation.rawValue)
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .frame(width: 14)
                        .foregroundStyle(event.operation.color)

                    // Main thread warning
                    if event.isMainThread {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 7))
                            .foregroundStyle(.red)
                    }

                    // Path (last 2 components)
                    Text(shortenPath(event.path))
                        .font(.system(size: 9, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.head)

                    Spacer()

                    // Size
                    if event.size > 0 && event.operation != .list {
                        Text(formatBytes(event.size))
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    if event.operation == .list {
                        Text("\(event.size) items")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    // Duration
                    Text(formatDuration(event.duration))
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(event.duration > 0.01 ? Color.orange : Color.secondary)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)

                Divider().padding(.leading, 24)
            }
        }

        private var diskSpaceRow: some View {
            HStack {
                if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
                   let total = attrs[.systemSize] as? Int64,
                   let free = attrs[.systemFreeSize] as? Int64
                {
                    let used = total - free
                    let pct = Double(used) / Double(total)

                    Text("Disk:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ProgressView(value: pct)
                        .controlSize(.small)
                        .frame(width: 80)

                    Text("\(formatBytes(free)) free")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }

        private func shortenPath(_ path: String) -> String {
            let components = (path as NSString).pathComponents
            if components.count <= 3 { return path }
            return ".../" + components.suffix(2).joined(separator: "/")
        }

        private func formatBytes(_ bytes: Int64) -> String {
            if bytes < 1024 { return "\(bytes)B" }
            if bytes < 1024 * 1024 { return "\(bytes / 1024)KB" }
            return String(format: "%.1fMB", Double(bytes) / (1024 * 1024))
        }

        private func formatDuration(_ d: TimeInterval) -> String {
            if d < 0.001 { return "<1ms" }
            if d < 1 { return String(format: "%.0fms", d * 1000) }
            return String(format: "%.2fs", d)
        }
    }

    // MARK: - Convenience installer

    public extension DebugDrawer {
        func installDiskIO() {
            DiskIOStore.shared.install()
            registerGlobal(DiskIOPlugin())
        }
    }
#endif
