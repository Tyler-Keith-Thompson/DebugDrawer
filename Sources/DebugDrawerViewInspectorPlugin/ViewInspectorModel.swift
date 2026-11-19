import Combine
import DebugDrawer
import Foundation

#if DEBUG
    // The model composes the overlay controller, the render tracker and the flash setting rather
    // than replacing them: `.debugGrid()`, `.trackRenders(_:)` and the iOS touch swap run in the
    // app's own views and windows, where no plugin is at hand, so they keep reaching the process's
    // one controller and tracker. The live UI (windows, views, layers, the overlay windows) stays
    // behind `ViewInspectorOverlayService` and `ViewHierarchyReader`; the model holds values only.

    /// The View Inspector plugin's state and behavior, without its views: the overlay switches,
    /// the animation speed, the render counts and the view hierarchy snapshot, read as a
    /// ``ViewInspectorSnapshot`` and changed with a ``ViewInspectorCommand``.
    ///
    /// The plugin's view reaches it through a `DebugDrawerPluginTransport`:
    ///
    /// ```swift
    /// let transport = DebugDrawerPluginTransport.direct(to: ViewInspectorModel.shared)
    /// ```
    ///
    /// It acts on the app's live windows, so it runs in the app's process. Release builds get a
    /// stand-in whose snapshot holds nothing and which ignores every command.
    @MainActor
    public final class ViewInspectorModel: DebugDrawerPluginModel {
        /// The model over ``ViewBorderController/shared`` and the render counts
        /// `.trackRenders(_:)` records, which the plugin shows.
        public static let shared = ViewInspectorModel()

        let overlays: any ViewInspectorOverlayService
        let hierarchyReader: any ViewHierarchyReader
        let renderTracker: RenderTracker
        let renderFlash: RenderFlashSetting

        /// The key window's hierarchy as last read, or `nil` when collapsed.
        @Published private var hierarchy: ViewNode?
        /// The drawers holding the plugin: it works while any does.
        private var drawers: Set<ObjectIdentifier> = []
        private var subscriptions: Set<AnyCancellable> = []

        /// - Parameters:
        ///   - overlays: Draws over the app's windows and slows their animations.
        ///   - hierarchyReader: Reads the key window's views.
        ///   - renderTracker: The counts `.trackRenders(_:)` records.
        ///   - renderFlash: Whether tracked views flash on each render.
        init(
            overlays: any ViewInspectorOverlayService = ViewBorderController.shared,
            hierarchyReader: any ViewHierarchyReader = _ViewHierarchyReader(),
            renderTracker: RenderTracker = .shared,
            renderFlash: RenderFlashSetting = .shared
        ) {
            self.overlays = overlays
            self.hierarchyReader = hierarchyReader
            self.renderTracker = renderTracker
            self.renderFlash = renderFlash
            overlays.objectWillChange
                .merge(with: renderTracker.objectWillChange, renderFlash.objectWillChange)
                .sink { [weak self] in self?.objectWillChange.send() }
                .store(in: &subscriptions)
        }

        public var snapshot: ViewInspectorSnapshot {
            ViewInspectorSnapshot(
                overlays: overlays.overlaySettings,
                isFlashingRenders: renderFlash.isOn,
                renderCounts: renderTracker.entries,
                hierarchy: hierarchy
            )
        }

        public func perform(_ command: ViewInspectorCommand) {
            switch command.action {
            case let .overlays(change): apply(change)
            case let .renders(change): apply(change)
            case let .hierarchy(change): apply(change)
            }
        }

        /// Starts counting renders and, on iOS, swaps in the touch observer, as `drawer` adds the
        /// plugin.
        func install(in drawer: ObjectIdentifier) {
            drawers.insert(drawer)
            renderTracker.isTracking = true
            overlays.install()
        }

        /// Once no drawer holds the plugin, turns every overlay, the slowed animations and the
        /// render flashes off, puts back what install changed, stops counting and forgets the
        /// counts and the hierarchy read.
        func uninstall(from drawer: ObjectIdentifier) {
            guard drawers.remove(drawer) != nil, drawers.isEmpty else { return }
            overlays.uninstall()
            renderFlash.isOn = false
            renderTracker.isTracking = false
            renderTracker.reset()
            hierarchy = nil
        }

        private func apply(_ change: ViewInspectorCommand.Overlays) {
            var settings = overlays.overlaySettings
            switch change {
            case let .setBordersEnabled(isOn): settings.isBordersEnabled = isOn
            case let .setGridEnabled(isOn): settings.isGridEnabled = isOn
            case let .setGridSpacing(spacing): settings.gridSpacing = spacing
            case let .setGridColor(color): settings.gridColor = color
            case let .setGridOpacity(opacity): settings.gridOpacity = opacity
            case let .setClickIndicatorEnabled(isOn): settings.isClickIndicatorEnabled = isOn
            case let .setAnimationSpeed(speed): settings.animationSpeed = speed
            }
            overlays.overlaySettings = settings
        }

        private func apply(_ change: ViewInspectorCommand.Renders) {
            switch change {
            case let .setFlashing(isOn): renderFlash.isOn = isOn
            case .reset: renderTracker.reset()
            }
        }

        private func apply(_ change: ViewInspectorCommand.Hierarchy) {
            switch change {
            case .snapshot:
                if let read = hierarchyReader.keyWindowHierarchy() { hierarchy = read }
            case .collapse:
                hierarchy = nil
            }
        }
    }
#else
    // The release stand-in: the same members, and nothing behind them.

    /// Release builds inspect nothing: this stand-in's snapshot holds nothing, and it ignores
    /// every command.
    @MainActor
    public final class ViewInspectorModel: DebugDrawerPluginModel {
        /// The stand-in model.
        public static let shared = ViewInspectorModel()

        private init() {}

        /// Always empty.
        public var snapshot: ViewInspectorSnapshot {
            ViewInspectorSnapshot()
        }

        /// Does nothing.
        ///
        /// - Parameter command: Ignored.
        public func perform(_ command: ViewInspectorCommand) {}
    }
#endif
