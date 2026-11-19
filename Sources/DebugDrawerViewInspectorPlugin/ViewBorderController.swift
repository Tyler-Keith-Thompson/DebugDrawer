#if DEBUG && (os(macOS) || os(iOS))
    import Combine
    import DebugDrawer
    import SwiftUI

    #if os(macOS)
        import AppKit
    #else
        // Mac Catalyst too: its windows are UIWindows in UIWindowScenes, as on iOS.
        import UIKit
    #endif

    // MARK: - Controller

    // Borders, ripples and the grid are drawn in windows of the drawer's own over the app's
    // (DrawerOverlayWindow), from the app's view frames read into values once per run-loop pass:
    // nothing is added to the app's windows and no layer property of theirs is set, so the app's
    // own snapshots and screenshots, and every layer property it reads, are what they would be
    // with the View Inspector off. Animation speed is the exception, since slowing the app's
    // animations is the feature: it sets the speed of each window's root layer and gives back the
    // speed that layer had.

    /// The View Inspector's switches over the app's windows: view borders by depth, the
    /// alignment grid `.debugGrid()` places, click indicators and slowed animations.
    @MainActor
    public final class ViewBorderController: ObservableObject {
        #if os(macOS)
            typealias Window = NSWindow
        #else
            typealias Window = UIWindow
        #endif

        /// The controller the View Inspector plugin and `.debugGrid()` share.
        public static let shared = ViewBorderController()

        /// Whether every view in the app's windows is outlined in a color by its depth.
        ///
        /// The outlines are drawn in a window of the drawer's own over each of the app's windows,
        /// so no view or layer of the app's changes and the app's own snapshots don't show them.
        @Published public var isBordersEnabled = false {
            didSet { overlaysDidChange() }
        }

        /// Whether the alignment grid is drawn over each view `.debugGrid()` is applied to.
        @Published public var isGridEnabled = false {
            didSet { overlaysDidChange() }
        }

        /// The grid's spacing in points.
        @Published public var gridSpacing: CGFloat = 8 {
            didSet { overlaysDidChange() }
        }

        /// The grid's color.
        @Published public var gridColor: GridColor = .blue {
            didSet { overlaysDidChange() }
        }

        /// The grid's opacity, from 0 to 1.
        @Published public var gridOpacity: Double = 0.15 {
            didSet { overlaysDidChange() }
        }

        // On iOS, installViewInspector() installed the touch swizzle, which reads this flag;
        // setting it swizzles nothing.
        /// Whether each click or touch in the app shows a ripple where it landed, drawn over the
        /// app's window rather than in it.
        @Published public var isClickIndicatorEnabled = false {
            didSet {
                #if os(macOS)
                    if isClickIndicatorEnabled {
                        clickMonitor.start()
                    } else {
                        clickMonitor.stop()
                    }
                #endif
                overlaysDidChange()
            }
        }

        /// How many times slower Core Animation runs in every window of the app: 1 is the
        /// windows' own speed, 10 is ten times slower.
        ///
        /// It divides the speed of each window's root layer, including windows opened later, and
        /// gives each layer back the exact speed it had when it returns to 1.
        @Published public var animationSpeed: Double = 1.0 {
            didSet { animationSpeedDidChange() }
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

        /// The overlay windows the outlines, grids and ripples are drawn in.
        let overlays = InspectorOverlays()
        private let appWindows: @MainActor () -> [Window]
        private let slowdown = AnimationSlowdown()
        private let gridProbes = NSHashTable<GridProbeView>.weakObjects()
        private var windowObservers: [any NSObjectProtocol] = []
        private lazy var passObserver = RunLoopPassObserver { [weak self] in self?.refreshOverlays() }
        #if os(macOS)
            private lazy var clickMonitor = ClickIndicatorMonitor { [weak self] event in self?.showRipple(for: event) }
        #endif

        /// A controller over the windows `appWindows` lists each time it is called.
        ///
        /// - Parameter appWindows: The app's windows to draw over and slow, without the drawer's
        ///   own; by default every visible one.
        init(appWindows: @escaping @MainActor () -> [Window] = ViewBorderController.visibleAppWindows) {
            self.appWindows = appWindows
        }

        /// The app's key window, not the drawer's when its search field has focus.
        static var keyWindow: Window? {
            debugDrawerAppKeyWindow
        }

        /// Whether any overlay is on, so the overlay windows must exist.
        private var needsOverlays: Bool {
            isBordersEnabled || isGridEnabled || isClickIndicatorEnabled
        }

        private var gridStyle: GridStyle {
            GridStyle(spacing: gridSpacing, color: gridColor.color, opacity: gridOpacity)
        }

        /// Starts or stops reading frames once per run-loop pass, and draws at once.
        private func overlaysDidChange() {
            guard needsOverlays else {
                passObserver.stop()
                overlays.removeAll()
                return
            }
            passObserver.start()
            refreshOverlays()
        }

        /// Turns every overlay and the slowed animations off: the overlay windows go, the run-loop
        /// observer and the click monitor stop, and every window's layer gets its own speed back.
        /// The grid's spacing, color and opacity stay as set.
        func turnEverythingOff() {
            isBordersEnabled = false
            isGridEnabled = false
            isClickIndicatorEnabled = false
            animationSpeed = 1
        }

        /// Records a view `.debugGrid()` placed behind its content, held weakly, whose frame is
        /// where the grid is drawn.
        func addGridProbe(_ probe: GridProbeView) {
            // Made while SwiftUI updates the app's view, so the probe is read in the next pass
            // rather than now.
            gridProbes.add(probe)
            passObserver.wakeUp()
        }

        /// Reads the outlines and grids of every app window into its overlay, and asks for one
        /// more pass when any changed, so it is drawn.
        func refreshOverlays() {
            guard needsOverlays else { return }
            var changed = false
            #if os(macOS)
                let windows = appWindows()
                for window in windows {
                    let overlay = overlays.overlay(over: window)
                    overlay.window.followHost()
                    let place = { (rect: CGRect) in overlay.window.convert(fromHost: rect) }
                    let outlines = isBordersEnabled ? window.contentView.map { ViewOutline.read(from: $0, placing: place) } ?? [] : []
                    let grids = isGridEnabled ? gridProbes.allObjects.filter { $0.window === window && !$0.isHiddenOrHasHiddenAncestor }
                        .map { place($0.convert($0.bounds, to: nil)) } : []
                    changed = overlay.model.update(outlines: outlines, grids: grids, gridStyle: gridStyle) || changed
                }
                overlays.keep(only: windows)
            #else
                let windows = appWindows().enumerated()
                    .sorted { ($0.element.windowLevel.rawValue, $0.offset) < ($1.element.windowLevel.rawValue, $1.offset) }
                    .map(\.element)
                var scenes: [UIWindowScene] = []
                for scene in windows.compactMap(\.windowScene) where !scenes.contains(where: { $0 === scene }) {
                    scenes.append(scene)
                }
                for scene in scenes {
                    let overlay = overlays.overlay(over: scene)
                    let sceneWindows = windows.filter { $0.windowScene === scene }
                    let outlines = isBordersEnabled ? ViewOutline.read(from: sceneWindows, in: overlay.window) : []
                    let grids: [CGRect] = isGridEnabled ? gridProbes.allObjects.compactMap { probe in
                        guard let window = probe.window, window.windowScene === scene, !probe.isHidden else { return nil }
                        return window.convert(probe.convert(probe.bounds, to: nil), to: overlay.window)
                    } : []
                    changed = overlay.model.update(outlines: outlines, grids: grids, gridStyle: gridStyle) || changed
                }
                overlays.keep(only: scenes)
            #endif
            if changed { passObserver.wakeUp() }
        }

        // MARK: Click indicators

        #if os(macOS)
            /// Shows a ripple over `window` at `point`, in the window's base coordinates, while
            /// click indicators are on; a click on the drawer's own window shows none.
            ///
            /// - Parameters:
            ///   - point: Where the click landed, in `window`'s base coordinates.
            ///   - window: The window clicked.
            func showRipple(at point: CGPoint, in window: NSWindow) {
                guard isClickIndicatorEnabled, !isDebugDrawerWindow(window) else { return }
                let overlay = overlays.overlay(over: window)
                overlay.window.followHost()
                overlay.model.addRipple(at: overlay.window.convert(fromHost: point))
            }

            private func showRipple(for event: NSEvent) {
                guard let window = event.window else { return }
                showRipple(at: event.locationInWindow, in: window)
            }
        #else
            /// Shows a ripple over `window`'s scene at `point`, in the window's coordinates, while
            /// click indicators are on; a touch on the drawer's own window, or in a window with no
            /// scene, shows none.
            ///
            /// - Parameters:
            ///   - point: Where the touch began, in `window`'s coordinates.
            ///   - window: The window touched.
            func showRipple(at point: CGPoint, in window: UIWindow) {
                guard isClickIndicatorEnabled, !isDebugDrawerWindow(window), let scene = window.windowScene else { return }
                let overlay = overlays.overlay(over: scene)
                overlay.model.addRipple(at: window.convert(point, to: overlay.window))
            }
        #endif

        // MARK: Animation speed

        /// Slows every app window to the new speed, or gives each its own back, and follows the
        /// windows opened while animations are slowed.
        private func animationSpeedDidChange() {
            applyAnimationSpeed()
            if animationSpeed == 1 {
                windowObservers.forEach(NotificationCenter.default.removeObserver)
                windowObservers.removeAll()
            } else if windowObservers.isEmpty {
                #if os(macOS)
                    // A window ordered in changes its occlusion state; one made key may be new.
                    let names = [NSWindow.didChangeOcclusionStateNotification, NSWindow.didBecomeKeyNotification]
                #else
                    let names = [UIWindow.didBecomeVisibleNotification]
                #endif
                for name in names {
                    windowObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                        MainActor.assumeIsolated { self?.applyAnimationSpeed() }
                    })
                }
            }
        }

        private func applyAnimationSpeed() {
            #if os(macOS)
                let layers = appWindows().compactMap { $0.contentView?.layer }
            #else
                let layers = appWindows().map(\.layer)
            #endif
            slowdown.apply(animationSpeed, to: layers)
        }

        /// Every window of the app that is on screen, without the drawer's own.
        static func visibleAppWindows() -> [Window] {
            #if os(macOS)
                NSApplication.shared.windows.filter { window in
                    window.isVisible && !isDebugDrawerWindow(window) && (window.canBecomeMain || window.sheetParent != nil)
                }
            #else
                UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .flatMap(\.windows)
                    .filter { !$0.isHidden && !isDebugDrawerWindow($0) }
            #endif
        }

        isolated deinit {
            windowObservers.forEach(NotificationCenter.default.removeObserver)
            slowdown.restore()
            overlays.removeAll()
        }
    }
#elseif !DEBUG
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
