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
        @NewestFirst public var events: [IOEvent]
        /// Every call since the last clear, including the ones ``events`` no longer keeps.
        @Published public private(set) var totals = DiskIOTotals()
        /// The operation the list shows alone, or `nil` for every operation.
        @Published public var filterOp: IOEvent.Operation?
        /// Whether the list shows only the calls made on the main thread.
        @Published public var mainThreadOnly = false

        /// How many calls ``events`` keeps, 500 unless set; the totals count every call regardless.
        public var capacity: Int {
            get { recorder.limit }
            set {
                recorder.limit = newValue
                objectWillChange.send()
                show(recorder.snapshot(from: shownEnd))
            }
        }

        /// How many bytes of paths ``events`` keeps, 1 MiB unless set; the oldest calls go when a
        /// new one would pass it, and the totals count every call regardless.
        public var byteCapacity: Int {
            get { recorder.byteLimit }
            set {
                recorder.byteLimit = newValue
                objectWillChange.send()
                show(recorder.snapshot(from: shownEnd))
            }
        }

        private var installed = false
        private let recorder: DiskIORecorder
        /// The recorder's buffer ID after the newest call in ``events``; the others count down
        /// from it.
        private var shownEnd = CaptureBuffer<IOEvent>.ElementID(rawValue: 0)
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
            recorder.clear()
            totals = DiskIOTotals()
            show(recorder.snapshot(from: shownEnd))
        }

        private func receive(_ batch: DiskIOBatch) {
            // Setting the totals sends `objectWillChange`, for the list too: a batch always holds
            // a call, and a second send would walk the store's properties again. Set rather than
            // `+=`, whose `modify` through `@Published` allocates for its coroutine and key path.
            var updated = totals
            updated += batch.totals
            totals = updated
            show(batch.events)
        }

        /// Brings the list up to `change`: the calls the buffer evicted leave it and the new ones
        /// join it, in place, so a delivery copies only the new calls. The caller sends
        /// `objectWillChange` first.
        private func show(_ change: CaptureBuffer<IOEvent>.Snapshot) {
            // `events` holds the buffer's IDs below `shownEnd`; a change can start before it when
            // the store asked for one itself since the recorder's last delivery.
            let shownAlready = shownEnd.rawValue - min(change.firstID.rawValue, shownEnd.rawValue)
            let new = change.elements.dropFirst(Int(min(shownAlready, UInt64(change.elements.count))))
            let kept = change.keptCount(of: _events.count, before: shownEnd)
            if kept < _events.count || !new.isEmpty {
                _events.update(keepingNewest: kept, appending: new)
            }
            shownEnd = max(shownEnd, change.endID)
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

        /// Kept, never used.
        public var byteCapacity = 1_048_576

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
