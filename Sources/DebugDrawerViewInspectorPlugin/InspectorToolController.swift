#if !DEBUG
    import Combine
    import Foundation

    // The release stand-in for the debug controller in InspectorToolController+macOS.swift and
    // +iOS.swift: the same members, so the host's code compiles unchanged, and no overlay window
    // or inspection behind them.

    /// Release builds inspect nothing: this stand-in keeps the debug build's members.
    @MainActor
    public final class InspectorToolController: ObservableObject {
        /// The stand-in controller.
        public static let shared = InspectorToolController()

        /// What a click on the window does.
        public enum Mode: Equatable {
            case off
            case measure
            case inspect
        }

        /// Kept, never read: release builds show no overlay.
        @Published public var mode: Mode = .off

        /// Always empty unless set.
        @Published public var selectedAttributes: [AttributeRow] = []

        /// Always nil unless set.
        @Published public var lastMeasureResult: MeasureResult?

        /// One attribute of an inspected view.
        public struct AttributeRow: Identifiable {
            /// The row's identity.
            public let id = UUID()
            /// The attribute's name.
            public let label: String
            /// The attribute's value.
            public let value: String
        }

        /// The distances between two measured views.
        public struct MeasureResult {
            /// The horizontal distance.
            public let horizontal: CGFloat
            /// The vertical distance.
            public let vertical: CGFloat
            /// The straight-line distance.
            public let diagonal: CGFloat
        }

        private init() {}

        /// Does nothing.
        public func clearPreviousSession() {}
    }
#endif
