#if !DEBUG
    import Combine
    import DebugDrawer
    import Foundation

    // The release stand-in of the store in DebugDrawerNetworkPlugin.swift: the same members, no
    // URL protocol or swizzling behind them, and no requests ever.

    /// Release builds capture no requests: this stand-in keeps the debug build's members.
    @MainActor
    public final class NetworkStore: ObservableObject {
        /// The stand-in store.
        public static let shared = NetworkStore()

        /// Always empty.
        @Published public private(set) var entries: [NetworkEntry] = []
        /// Kept, never applied.
        @Published public var filterText = ""
        /// Kept, never applied.
        @Published public var filterStatus: StatusFilter = .all

        /// Kept, never used.
        public private(set) var capacity = 200

        /// Kept, never used.
        public private(set) var byteCapacity = 32 * 1_048_576

        /// Keeps `capacity`, never using it.
        ///
        /// - Throws: `CaptureBuffer.InvalidLimit.negativeMaxCount` when `capacity` is negative,
        ///   changing nothing.
        public func setCapacity(_ capacity: Int) throws(CaptureBuffer<NetworkEntry>.InvalidLimit) {
            guard capacity >= 0 else { throw .negativeMaxCount }
            self.capacity = capacity
        }

        /// Keeps `byteCapacity`, never using it.
        ///
        /// - Throws: `CaptureBuffer.InvalidLimit.negativeMaxByteCount` when `byteCapacity` is
        ///   negative, changing nothing.
        public func setByteCapacity(_ byteCapacity: Int) throws(CaptureBuffer<NetworkEntry>.InvalidLimit) {
            guard byteCapacity >= 0 else { throw .negativeMaxByteCount }
            self.byteCapacity = byteCapacity
        }

        /// Always empty.
        public var filteredEntries: [NetworkEntry] {
            []
        }

        private init() {}

        /// Does nothing: release builds intercept nothing.
        public func install() {}

        /// Does nothing: release builds intercept nothing.
        public func uninstall() {}

        /// Does nothing.
        public func clear() {}
    }
#endif
