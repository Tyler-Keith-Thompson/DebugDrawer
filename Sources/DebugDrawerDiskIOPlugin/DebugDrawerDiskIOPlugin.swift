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
        public var category = "Storage"
        public var icon = "externaldrive"

        public init() {}

        public var body: some View {
            DiskIOPluginView()
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
