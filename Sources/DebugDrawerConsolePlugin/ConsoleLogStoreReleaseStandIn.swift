#if !DEBUG
    import Combine
    import DebugDrawer
    import Foundation

    // The release stand-in of the store in DebugDrawerConsolePlugin.swift: the same members, so
    // the host's code compiles unchanged, and no stdout, stderr or os_log capture behind them.

    /// Release builds capture nothing: this stand-in keeps the debug build's members.
    @MainActor
    public final class ConsoleLogStore: ObservableObject {
        /// The stand-in store.
        public static let shared = ConsoleLogStore()

        /// Always empty: release builds capture nothing.
        @Published public private(set) var lines: [LogLine] = []
        /// How many older lines the bounds dropped since the store was made or last cleared.
        @Published private(set) var droppedLineCount = 0

        /// Kept, never read: release builds list nothing.
        public var filterLevel: LogLine.Level = .debug

        /// Kept, never read: release builds keep no lines.
        public private(set) var capacity = 2000

        /// Kept, never read: release builds keep no lines.
        public private(set) var byteCapacity = 4 * 1_048_576

        /// Keeps `capacity`, never reading it.
        ///
        /// - Throws: `CaptureBuffer.InvalidLimit.negativeMaxCount` when `capacity` is negative,
        ///   changing nothing.
        public func setCapacity(_ capacity: Int) throws(CaptureBuffer<LogLine>.InvalidLimit) {
            guard capacity >= 0 else { throw .negativeMaxCount }
            self.capacity = capacity
        }

        /// Keeps `byteCapacity`, never reading it.
        ///
        /// - Throws: `CaptureBuffer.InvalidLimit.negativeMaxByteCount` when `byteCapacity` is
        ///   negative, changing nothing.
        public func setByteCapacity(_ byteCapacity: Int) throws(CaptureBuffer<LogLine>.InvalidLimit) {
            guard byteCapacity >= 0 else { throw .negativeMaxByteCount }
            self.byteCapacity = byteCapacity
        }

        /// Always empty.
        public var filteredLines: [LogLine] {
            []
        }

        private init() {}

        /// Does nothing: release builds capture nothing.
        public func install() {}

        /// Does nothing: release builds capture nothing.
        public func uninstall() {}

        /// Does nothing.
        public func clear() {}
    }
#endif
