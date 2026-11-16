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

    @MainActor
    public final class ViewBorderController: ObservableObject {
        public static let shared = ViewBorderController()

        @Published public var isBordersEnabled = false {
            didSet { isBordersEnabled ? startObserving() : stopObserving() }
        }

        @Published public var isGridEnabled = false
        @Published public var gridSpacing: CGFloat = 8
        @Published public var gridColor: GridColor = .blue
        @Published public var gridOpacity: Double = 0.15

        @Published public var isClickIndicatorEnabled = false {
            didSet { isClickIndicatorEnabled ? ClickIndicatorMonitor.shared.start() : ClickIndicatorMonitor.shared.stop() }
        }

        @Published public var animationSpeed: Double = 1.0 {
            didSet {
                guard let window = NSApp?.keyWindow else { return }
                window.contentView?.layer?.speed = animationSpeed == 1.0 ? 1.0 : Float(1.0 / animationSpeed)
            }
        }

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
                    guard let view, view.window == NSApp?.keyWindow,
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
            guard let window = NSApp?.keyWindow else { return }
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

    @MainActor
    public final class ViewBorderController: ObservableObject {
        public static let shared = ViewBorderController()

        @Published public var isBordersEnabled = false {
            didSet { isBordersEnabled ? applyBorders() : removeBorders() }
        }

        @Published public var isGridEnabled = false
        @Published public var gridSpacing: CGFloat = 8
        @Published public var gridColor: GridColor = .blue
        @Published public var gridOpacity: Double = 0.15

        @Published public var isClickIndicatorEnabled = false {
            didSet { isClickIndicatorEnabled ? ClickIndicatorMonitor.shared.start() : ClickIndicatorMonitor.shared.stop() }
        }

        @Published public var animationSpeed: Double = 1.0 {
            didSet {
                guard let window = Self.keyWindow else { return }
                window.layer.speed = animationSpeed == 1.0 ? 1.0 : Float(1.0 / animationSpeed)
            }
        }

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

        static var keyWindow: UIWindow? {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first(where: { $0.activationState == .foregroundActive })?
                .windows.first(where: { $0.isKeyWindow })
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
#endif
