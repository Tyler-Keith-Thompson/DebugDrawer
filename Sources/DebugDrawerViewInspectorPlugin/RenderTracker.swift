#if !DEBUG
    import Combine
    import Foundation

    // The release stand-in for the debug tracker in SwiftUIRenderTracker.swift: the same members,
    // so the host's code compiles unchanged, and nothing swizzled or counted behind them.

    /// Release builds count no renders: this stand-in keeps the debug build's members.
    @MainActor
    public final class RenderTracker: ObservableObject {
        /// The stand-in tracker.
        public static let shared = RenderTracker()

        /// Kept, never read: release builds track nothing.
        @Published public var isEnabled = false

        /// Kept, never read.
        @Published public var showOverlays = true

        /// Always empty.
        @Published public private(set) var renderCounts: [String: Int] = [:]

        /// Always empty.
        @Published public private(set) var lastRenderTimes: [String: Date] = [:]

        private init() {}

        /// Does nothing.
        ///
        /// - Parameter id: Ignored.
        public func recordRender(_ id: String) {}

        /// Does nothing.
        public func reset() {}

        /// A view type's render count and when it last rendered.
        public struct Entry: Identifiable, Equatable {
            /// The view type's name.
            public let id: String
            /// How many times it rendered.
            public let count: Int
            /// When it last rendered.
            public let lastRender: Date
        }

        /// Always empty.
        public var sortedEntries: [Entry] {
            []
        }

        /// Always zero.
        public var totalRenders: Int {
            0
        }
    }
#endif
