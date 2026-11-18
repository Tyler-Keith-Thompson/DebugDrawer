import Combine
import DebugDrawer
import Foundation
import SwiftUI

// MARK: - Plugin

// The public API compiles in every configuration; the implementation under `#if DEBUG` below does
// not, so release builds get an empty view and an installer that swizzles and registers nothing.

/// The app's file calls as they happen: reads, writes, creates, deletes, listings, stats, copies
/// and moves, each with its path, size, duration, thread and error, and running totals of them.
///
/// `installDiskIO()` swizzles these, and records each call the app makes through them:
///
/// - `FileManager`: `contents(atPath:)`, `createFile(atPath:contents:attributes:)`,
///   `createDirectory` (path and URL), `removeItem`, `contentsOfDirectory`, `copyItem` and
///   `moveItem` (each by path and by URL), and `attributesOfItem(atPath:)`;
/// - `NSData`: `write(toFile:)` and `write(to:)` (with `atomically:` or `options:`), and its
///   `contentsOfFile:` and `contentsOf:` initializers;
/// - `FileHandle`: the Objective-C reads and writes (`readData(ofLength:)`, `readDataToEndOfFile()`,
///   `availableData`, `read(upToCount:)`, `readToEnd()`, `write(_:)`) on regular files.
///
/// On current OSes these never reach a swizzled method, so `installDiskIO()` doesn't record them:
/// Swift's `Data.write(to:)`, `Data(contentsOf:)` and `FileHandle.write(contentsOf:)`, `String`'s
/// file methods, POSIX calls (`open`, `read`, `write`), SQLite, Core Data and `UserDefaults`. Nor
/// is a `FileHandle` call that fails, or the drawer's own file work, which runs with
/// `DebugDrawerActivity.isDrawerWork` bound to `true`.
///
/// `unsafeInstallDiskIOWithInterposing()`, in an app that links the `DebugDrawerDiskIOInterposer`
/// dynamic library, records those too: each `read`, `write`, `pread` and `pwrite` on a regular
/// file that no swizzled method records, through dyld interposing.
public struct DiskIOPlugin: DebugDrawerPlugin {
    public var title = "Disk I/O"
    public var category = "Storage"
    public var icon = "externaldrive"

    public init() {}

    public var body: some View {
        #if DEBUG
            DiskIOPluginView()
        #else
            EmptyView()
        #endif
    }
}

// MARK: - Convenience installer

public extension DebugDrawer {
    /// Swizzles the file methods ``DiskIOPlugin`` lists and registers the plugin.
    func installDiskIO() {
        #if DEBUG
            DiskIOStore.shared.install()
            registerGlobal(DiskIOPlugin())
        #endif
    }

    /// Does what ``installDiskIO()`` does, and also records Swift's `Data.write(to:)`,
    /// `Data(contentsOf:)` and `FileHandle.write(contentsOf:)`, through dyld interposing.
    ///
    /// Unsafe: interposing is undocumented dyld behaviour that a new OS can change or drop, and
    /// it runs the plugin's code inside every `read`, `write`, `pread` and `pwrite` the process
    /// makes. It needs the app to link the `DebugDrawerDiskIOInterposer` dynamic library, which
    /// dyld must load at launch. Without it, and before iOS 18, where swizzling already sees those
    /// calls, this does what ``installDiskIO()`` does.
    func unsafeInstallDiskIOWithInterposing() {
        #if DEBUG
            DiskIOStore.shared.unsafeInstallWithInterposing()
            registerGlobal(DiskIOPlugin())
        #endif
    }
}

#if DEBUG
    // MARK: - I/O monitor store

    /// The recorded calls, newest first, and the totals of every call since the last clear.
    @MainActor
    public final class DiskIOStore: ObservableObject {
        /// The store `installDiskIO()` fills and the plugin shows.
        public static let shared = DiskIOStore(recorder: .shared)

        /// The newest calls, at most ``capacity``, newest first.
        @Published public private(set) var events: [IOEvent] = []
        /// Every call since the last clear, including the ones ``events`` no longer keeps.
        @Published public private(set) var totals = DiskIOTotals()
        /// The operation the list shows alone, or `nil` for every operation.
        @Published public var filterOp: IOEvent.Operation?
        /// Whether the list shows only the calls made on the main thread.
        @Published public var mainThreadOnly = false

        /// How many calls ``events`` keeps, 500 unless set; the totals count every call regardless.
        public var capacity = 500 {
            didSet { recorder.setLimit(capacity) }
        }

        private var installed = false
        private let recorder: DiskIORecorder
        private var cancellable: AnyCancellable?

        /// The reads since the last clear.
        public var totalReads: Int {
            totals.reads
        }

        /// The writes since the last clear.
        public var totalWrites: Int {
            totals.writes
        }

        /// The bytes read since the last clear.
        public var totalBytesRead: Int64 {
            totals.bytesRead
        }

        /// The bytes written since the last clear.
        public var totalBytesWritten: Int64 {
            totals.bytesWritten
        }

        /// The calls made on the main thread since the last clear.
        public var mainThreadOps: Int {
            totals.mainThreadCalls
        }

        /// The kept calls that pass ``filterOp`` and ``mainThreadOnly``, newest first.
        public var filteredEvents: [IOEvent] {
            var result = events
            if let op = filterOp { result = result.filter { $0.operation == op } }
            if mainThreadOnly { result = result.filter(\.isMainThread) }
            return result
        }

        /// A store showing what `recorder` records.
        init(recorder: DiskIORecorder) {
            self.recorder = recorder
            cancellable = recorder.batches.sink { [weak self] batch in
                self?.receive(batch)
            }
        }

        /// Swizzles the file methods ``DiskIOPlugin`` lists, so the app's calls through them are
        /// recorded. `installDiskIO()` calls it; a second call does nothing.
        public func install() {
            guard !installed else { return }
            installed = true
            DiskIOSwizzler.install()
        }

        /// Does what ``install()`` does, then turns on the DebugDrawerDiskIOInterposer library's
        /// hooks, so Swift's `Data.write(to:)`, `Data(contentsOf:)` and
        /// `FileHandle.write(contentsOf:)` are recorded too.
        ///
        /// Unsafe: the library relies on dyld interposing, undocumented behaviour that a new OS can
        /// change or drop. It records each `read`, `write`, `pread` and `pwrite` on a regular file
        /// that no swizzled method records. Where the app doesn't link the library, or where
        /// swizzling already sees those calls (before iOS 18), it does what ``install()`` does.
        /// `unsafeInstallDiskIOWithInterposing()` calls it; a second call does nothing.
        public func unsafeInstallWithInterposing() {
            install()
            DiskIOInterposer.start()
        }

        /// Forgets the recorded calls and starts the totals over.
        public func clear() {
            events.removeAll()
            totals = DiskIOTotals()
        }

        private func receive(_ batch: DiskIOBatch) {
            totals += batch.totals
            guard !batch.events.isEmpty else { return }
            // Built whole and assigned once: `@Published` has no in-place mutation, so inserting
            // and trimming in place would copy the list twice.
            var newest = Array(batch.events.reversed().prefix(capacity))
            newest.append(contentsOf: events.prefix(max(capacity - newest.count, 0)))
            events = newest
        }
    }
#else
    // The release stand-in: the same members, no swizzling behind them, and no events ever.

    /// Release builds record no disk I/O: this stand-in keeps the debug build's members.
    @MainActor
    public final class DiskIOStore: ObservableObject {
        /// The stand-in store.
        public static let shared = DiskIOStore()

        /// Always empty.
        @Published public private(set) var events: [IOEvent] = []
        /// Always zero.
        @Published public private(set) var totals = DiskIOTotals()
        /// Kept, never applied.
        @Published public var filterOp: IOEvent.Operation?
        /// Kept, never applied.
        @Published public var mainThreadOnly = false

        /// Kept, never used.
        public var capacity = 500

        /// Always zero.
        public var totalReads: Int {
            0
        }

        /// Always zero.
        public var totalWrites: Int {
            0
        }

        /// Always zero.
        public var totalBytesRead: Int64 {
            0
        }

        /// Always zero.
        public var totalBytesWritten: Int64 {
            0
        }

        /// Always zero.
        public var mainThreadOps: Int {
            0
        }

        /// Always empty.
        public var filteredEvents: [IOEvent] {
            []
        }

        private init() {}

        /// Does nothing: release builds swizzle nothing.
        public func install() {}

        /// Does nothing: release builds swizzle and interpose nothing.
        public func unsafeInstallWithInterposing() {}

        /// Does nothing.
        public func clear() {}
    }
#endif
