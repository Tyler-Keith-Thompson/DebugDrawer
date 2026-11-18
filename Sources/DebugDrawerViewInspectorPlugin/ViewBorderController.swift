#if DEBUG
    import Combine
    import DebugDrawer
    import SwiftUI

    #if os(macOS)
    import AppKit
    #elseif os(iOS)
    import UIKit
    #endif

    // MARK: - Controller

    #if os(macOS)

    /// The View Inspector's switches over the app's key window: view borders by depth, the
    /// alignment grid `.debugGrid()` draws, click indicators and the animation speed.
    @MainActor
    public final class ViewBorderController: ObservableObject {
        /// The controller the View Inspector plugin and `.debugGrid()` share.
        public static let shared = ViewBorderController()

        /// Whether every view in the key window has a border colored by its depth.
        @Published public var isBordersEnabled = false {
            didSet { isBordersEnabled ? startObserving() : stopObserving() }
        }

        /// Whether `.debugGrid()` draws its grid.
        @Published public var isGridEnabled = false
        /// The grid's spacing in points.
        @Published public var gridSpacing: CGFloat = 8
        /// The grid's color.
        @Published public var gridColor: GridColor = .blue
        /// The grid's opacity, from 0 to 1.
        @Published public var gridOpacity: Double = 0.15

        /// Whether each click or touch in the app shows a ripple where it landed.
        @Published public var isClickIndicatorEnabled = false {
            didSet { isClickIndicatorEnabled ? ClickIndicatorMonitor.shared.start() : ClickIndicatorMonitor.shared.stop() }
        }

        /// How many times slower the key window's Core Animation runs: 1 is normal speed.
        @Published public var animationSpeed: Double = 1.0 {
            didSet {
                guard let window = debugDrawerAppKeyWindow else { return }
                window.contentView?.layer?.speed = animationSpeed == 1.0 ? 1.0 : Float(1.0 / animationSpeed)
            }
        }

        /// The grid's color.
        public enum GridColor: String, CaseIterable {
            case blue, red, green, white, gray

            var color: Color {
                switch self {
                case .blue: .blue
                case .red: .red
                case .green: .green
                case .white: .white
                case .gray: .gray
                }
            }
        }

        private var taggedViews: [NSView] = []
        private var hierarchyObserver: Any?

        private init() {}

        private func startObserving() {
            applyBorders()
            guard hierarchyObserver == nil else { return }
            hierarchyObserver = NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                // Delivered on the main queue (`queue: .main` above), so the view never leaves it.
                let view = notification.object as? NSView
                MainActor.assumeIsolated {
                    guard let view, view.window == debugDrawerAppKeyWindow,
                          let self, self.isBordersEnabled else { return }
                    self.applyBorders()
                }
            }
        }

        private func stopObserving() {
            removeBorders()
            if let obs = hierarchyObserver {
                NotificationCenter.default.removeObserver(obs)
                hierarchyObserver = nil
            }
        }

        private func applyBorders() {
            guard let window = debugDrawerAppKeyWindow else { return }
            removeBorders()
            addBorders(to: window.contentView, depth: 0)
        }

        private func addBorders(to view: NSView?, depth: Int) {
            guard let view else { return }
            view.wantsLayer = true
            view.layer?.borderWidth = 1
            view.layer?.borderColor = Self.colorForDepth(depth).cgColor
            taggedViews.append(view)
            for sub in view.subviews {
                addBorders(to: sub, depth: depth + 1)
            }
        }

        private func removeBorders() {
            for view in taggedViews {
                view.layer?.borderWidth = 0
                view.layer?.borderColor = nil
            }
            taggedViews.removeAll()
        }

        private static func colorForDepth(_ depth: Int) -> NSColor {
            let hue = CGFloat(depth % 12) / 12.0
            return NSColor(hue: hue, saturation: 0.8, brightness: 0.9, alpha: 0.6)
        }
    }

    #elseif os(iOS)

    /// The View Inspector's switches over the app's key window: view borders by depth, the
    /// alignment grid `.debugGrid()` draws, click indicators and the animation speed.
    @MainActor
    public final class ViewBorderController: ObservableObject {
        /// The controller the View Inspector plugin and `.debugGrid()` share.
        public static let shared = ViewBorderController()

        /// Whether every view in the key window has a border colored by its depth.
        @Published public var isBordersEnabled = false {
            didSet { isBordersEnabled ? applyBorders() : removeBorders() }
        }

        /// Whether `.debugGrid()` draws its grid.
        @Published public var isGridEnabled = false
        /// The grid's spacing in points.
        @Published public var gridSpacing: CGFloat = 8
        /// The grid's color.
        @Published public var gridColor: GridColor = .blue
        /// The grid's opacity, from 0 to 1.
        @Published public var gridOpacity: Double = 0.15

        // installViewInspector() installed the touch swizzle, which reads this flag; setting it
        // swizzles nothing.
        /// Whether each click or touch in the app shows a ripple where it landed.
        @Published public var isClickIndicatorEnabled = false

        /// How many times slower the key window's Core Animation runs: 1 is normal speed.
        @Published public var animationSpeed: Double = 1.0 {
            didSet {
                guard let window = Self.keyWindow else { return }
                window.layer.speed = animationSpeed == 1.0 ? 1.0 : Float(1.0 / animationSpeed)
            }
        }

        /// The grid's color.
        public enum GridColor: String, CaseIterable {
            case blue, red, green, white, gray

            var color: Color {
                switch self {
                case .blue: .blue
                case .red: .red
                case .green: .green
                case .white: .white
                case .gray: .gray
                }
            }
        }

        private var taggedViews: [UIView] = []

        private init() {}

        /// The app's key window, not the drawer's when its search field has focus.
        static var keyWindow: UIWindow? {
            debugDrawerAppKeyWindow
        }

        private func applyBorders() {
            guard let window = Self.keyWindow else { return }
            removeBorders()
            addBorders(to: window, depth: 0)
        }

        private func addBorders(to view: UIView, depth: Int) {
            view.layer.borderWidth = 1
            view.layer.borderColor = Self.colorForDepth(depth).cgColor
            taggedViews.append(view)
            for sub in view.subviews {
                addBorders(to: sub, depth: depth + 1)
            }
        }

        private func removeBorders() {
            for view in taggedViews {
                view.layer.borderWidth = 0
                view.layer.borderColor = nil
            }
            taggedViews.removeAll()
        }

        private static func colorForDepth(_ depth: Int) -> UIColor {
            let hue = CGFloat(depth % 12) / 12.0
            return UIColor(hue: hue, saturation: 0.8, brightness: 0.9, alpha: 0.6)
        }
    }

    #endif
#else
    import Combine
    import CoreGraphics

    // The release stand-in: the same members, so the host's code compiles unchanged, and no
    // borders, grid, click indicators or animation changes behind them.

    /// Release builds draw no borders or grid: this stand-in keeps the debug build's members.
    @MainActor
    public final class ViewBorderController: ObservableObject {
        /// The stand-in controller.
        public static let shared = ViewBorderController()

        /// Kept, never read: release builds draw no borders.
        @Published public var isBordersEnabled = false
        /// Kept, never read: release builds draw no grid.
        @Published public var isGridEnabled = false
        /// Kept, never read.
        @Published public var gridSpacing: CGFloat = 8
        /// Kept, never read.
        @Published public var gridColor: GridColor = .blue
        /// Kept, never read.
        @Published public var gridOpacity: Double = 0.15
        /// Kept, never read: release builds show no click indicators.
        @Published public var isClickIndicatorEnabled = false
        /// Kept, never read: release builds leave animations at their speed.
        @Published public var animationSpeed: Double = 1.0

        /// The grid's color.
        public enum GridColor: String, CaseIterable {
            case blue, red, green, white, gray
        }

        private init() {}
    }
#endif
