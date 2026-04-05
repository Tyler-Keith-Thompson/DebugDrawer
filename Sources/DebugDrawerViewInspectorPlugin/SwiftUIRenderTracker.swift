#if DEBUG
    import ObjectiveC
    import SwiftUI

    #if os(macOS)
    import AppKit
    #elseif os(iOS)
    import UIKit
    #endif

    // MARK: - Render tracker

    @MainActor
    public final class RenderTracker: ObservableObject {
        public static let shared = RenderTracker()

        @Published public var isEnabled = false {
            didSet {
                if isEnabled, !swizzled { installSwizzles() }
            }
        }

        @Published public var showOverlays = true

        /// Published snapshot — updated periodically, NOT on every render.
        @Published public private(set) var renderCounts: [String: Int] = [:]
        @Published public private(set) var lastRenderTimes: [String: Date] = [:]

        /// Non-published backing storage — written from the swizzle path
        /// without triggering SwiftUI observation (which would cause recursion).
        var _counts: [String: Int] = [:]
        var _times: [String: Date] = [:]
        private var _flushScheduled = false

        var activeOverlays: Set<String> = []
        private var swizzled = false

        private init() {}

        /// Called from the swizzle — writes to non-published backing storage
        /// and schedules a batched flush to the published properties.
        public func recordRender(_ id: String) {
            guard isEnabled else { return }
            _counts[id, default: 0] += 1
            _times[id] = Date()

            if !_flushScheduled {
                _flushScheduled = true
                // Flush on next run loop — after the layout pass completes.
                DispatchQueue.main.async { [weak self] in
                    self?.flushToPublished()
                }
            }
        }

        private func flushToPublished() {
            _flushScheduled = false
            renderCounts = _counts
            lastRenderTimes = _times
        }

        public func reset() {
            _counts.removeAll()
            _times.removeAll()
            renderCounts.removeAll()
            lastRenderTimes.removeAll()
        }

        public var sortedEntries: [(id: String, count: Int, lastRender: Date)] {
            renderCounts.map { (id: $0.key, count: $0.value, lastRender: lastRenderTimes[$0.key] ?? .distantPast) }
                .sorted { $0.count > $1.count }
        }

        public var totalRenders: Int {
            renderCounts.values.reduce(0, +)
        }

        // MARK: - Swizzling

        private func installSwizzles() {
            guard !swizzled else { return }
            swizzled = true

            #if os(macOS)
            // Swizzle layout — called when needsLayout is set
            swizzleMethod(
                cls: NSView.self,
                original: #selector(NSView.layout),
                swizzled: #selector(NSView.dd_swizzledLayout)
            )

            // Swizzle updateLayer — called when wantsUpdateLayer is true
            swizzleMethod(
                cls: NSView.self,
                original: #selector(NSView.updateLayer),
                swizzled: #selector(NSView.dd_swizzledUpdateLayer)
            )

            // Also swizzle setNeedsDisplay — set when SwiftUI invalidates a view
            swizzleMethod(
                cls: NSView.self,
                original: #selector(setter: NSView.needsDisplay),
                swizzled: #selector(NSView.dd_swizzledSetNeedsDisplay(_:))
            )
            #elseif os(iOS)
            // Only swizzle layoutSubviews — setNeedsDisplay fires too often on iOS
            // and causes performance issues. This matches DebugSwift's approach.
            swizzleMethod(
                cls: UIView.self,
                original: #selector(UIView.layoutSubviews),
                swizzled: #selector(UIView.dd_swizzledLayoutSubviews)
            )
            #endif
        }

        private func swizzleMethod(cls: AnyClass, original: Selector, swizzled: Selector) {
            guard let originalMethod = class_getInstanceMethod(cls, original),
                  let swizzledMethod = class_getInstanceMethod(cls, swizzled)
            else { return }
            method_exchangeImplementations(originalMethod, swizzledMethod)
        }
    }

    // MARK: - Swizzled methods

    #if os(macOS)

    extension NSView {
        /// Patterns that identify SwiftUI hosting/infrastructure views on macOS.
        private static let swiftUIPatterns = [
            "NSHostingView",
            "PlatformViewHost",
            "PlatformViewRepresentable",
            "SwiftUI",
            "_SwiftUI",
            "DisplayList",
            "ViewGraph",
            "HostingView",
        ]

        fileprivate var isSwiftUIView: Bool {
            let name = String(describing: type(of: self))
            return Self.swiftUIPatterns.contains(where: { name.contains($0) })
        }

        /// Names that are SwiftUI infrastructure, not user views.
        private static let ignoredNames: Set<String> = [
            "AnyView", "ModifiedContent", "Optional", "SheetContent",
            "EnvironmentKeyWritingModifier", "DisplayList", "ViewGraph",
            "NSHostingView", "_NSHostingView", "PlatformViewHost",
            "PlatformViewRepresentable", "ViewHost", "HostingView",
            "any", "Body", "Never", "Content", "Some",
        ]

        fileprivate func extractViewTypeName() -> String? {
            let fullName = String(describing: type(of: self))

            let patterns = [
                "(?<=<)[A-Z][A-Za-z]+(?=View[,>])",
                "(?<=<)[A-Z][A-Za-z]{2,}(?=[,>])",
                "([A-Z][a-z]+)+(?=>)",
            ]

            for pattern in patterns {
                if let range = fullName.range(of: pattern, options: .regularExpression) {
                    let match = String(fullName[range])
                    if !match.hasPrefix("Modified"), !match.hasPrefix("_"),
                       !match.hasPrefix("Environment"),
                       !Self.ignoredNames.contains(match)
                    {
                        return match
                    }
                }
            }

            return nil
        }

        // Associated object keys for throttling
        private static var lastFlashTimeKey: UInt8 = 0
        private static var currentOverlayKey: UInt8 = 0
        private static var currentBadgeKey: UInt8 = 0

        private var lastFlashTime: CFAbsoluteTime {
            get { (objc_getAssociatedObject(self, &Self.lastFlashTimeKey) as? NSNumber)?.doubleValue ?? 0 }
            set { objc_setAssociatedObject(self, &Self.lastFlashTimeKey, NSNumber(value: newValue), .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
        }

        private var currentOverlay: NSView? {
            get { objc_getAssociatedObject(self, &Self.currentOverlayKey) as? NSView }
            set { objc_setAssociatedObject(self, &Self.currentOverlayKey, newValue, .OBJC_ASSOCIATION_ASSIGN) }
        }

        private var currentBadge: NSTextField? {
            get { objc_getAssociatedObject(self, &Self.currentBadgeKey) as? NSTextField }
            set { objc_setAssociatedObject(self, &Self.currentBadgeKey, newValue, .OBJC_ASSOCIATION_ASSIGN) }
        }

        private func notifyRenderIfNeeded() {
            guard RenderTracker.shared.isEnabled, isSwiftUIView else { return }

            guard let viewType = extractViewTypeName() else { return }
            RenderTracker.shared.recordRender(viewType)

            guard RenderTracker.shared.showOverlays else { return }

            // Throttle: at most one flash per view per 0.5s
            let now = CFAbsoluteTimeGetCurrent()
            guard now - lastFlashTime > 0.5 else {
                // Just update the badge count on the existing overlay if there is one
                if let badge = currentBadge {
                    let count = RenderTracker.shared.renderCounts[viewType] ?? 0
                    badge.stringValue = "\(count)"
                    badge.backgroundColor = count <= 5 ? .systemGreen : count <= 20 ? .systemOrange : .systemRed
                    badge.sizeToFit()
                }
                return
            }
            lastFlashTime = now

            showRenderFlash()
        }

        @objc func dd_swizzledLayout() {
            dd_swizzledLayout()
            notifyRenderIfNeeded()
        }

        @objc func dd_swizzledUpdateLayer() {
            dd_swizzledUpdateLayer()
            notifyRenderIfNeeded()
        }

        @objc func dd_swizzledSetNeedsDisplay(_ flag: Bool) {
            dd_swizzledSetNeedsDisplay(flag)
            if flag { notifyRenderIfNeeded() }
        }

        private func showRenderFlash() {
            // Remove existing overlay if any
            currentOverlay?.removeFromSuperview()

            wantsLayer = true

            let overlay = NSView(frame: bounds)
            overlay.wantsLayer = true
            overlay.layer?.borderWidth = 2
            overlay.layer?.borderColor = NSColor.systemOrange.withAlphaComponent(0.7).cgColor
            overlay.layer?.cornerRadius = 2
            addSubview(overlay)
            currentOverlay = overlay

            let viewType = extractViewTypeName() ?? "Unknown"
            let count = RenderTracker.shared.renderCounts[viewType] ?? 0

            let badge = NSTextField(labelWithString: "\(count)")
            badge.font = .monospacedSystemFont(ofSize: 8, weight: .bold)
            badge.textColor = .white
            badge.backgroundColor = count <= 5 ? .systemGreen : count <= 20 ? .systemOrange : .systemRed
            badge.drawsBackground = true
            badge.isBezeled = false
            badge.alignment = .center
            badge.sizeToFit()
            badge.frame.origin = CGPoint(
                x: bounds.width - badge.frame.width - 2,
                y: bounds.height - badge.frame.height - 2
            )
            overlay.addSubview(badge)
            currentBadge = badge

            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.8
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                overlay.animator().alphaValue = 0
            } completionHandler: { [weak self, weak overlay] in
                overlay?.removeFromSuperview()
                if self?.currentOverlay === overlay {
                    self?.currentOverlay = nil
                    self?.currentBadge = nil
                }
            }
        }
    }

    #elseif os(iOS)

    // DebugSwift-style render tracking for iOS.
    // Uses NSStringFromClass for Obj-C names, instance-based tracking with
    // ObjectIdentifier, activeOverlays Set for recursion guard, and overlays
    // added to the window (not the view).

    extension UIView {
        /// Matches DebugSwift's isSwiftUIHostingView — uses Obj-C class names.
        fileprivate var isSwiftUIHostingView: Bool {
            let className = NSStringFromClass(type(of: self))
            return className.contains("UIHosting") ||
                className.contains("SwiftUI") ||
                className.contains("_UIHosting") ||
                className.contains("_SwiftUI") ||
                className.hasPrefix("SwiftUI.") ||
                className.contains("ViewHost") ||
                className.contains("PlatformView") ||
                className.contains("DisplayList") ||
                className.contains("ViewGraph")
        }

        /// Matches DebugSwift's detectSwiftUIViewType.
        fileprivate func detectSwiftUIViewType() -> String {
            let className = NSStringFromClass(type(of: self))
            if className.contains("UIHostingView") { return "UIHostingView" }
            if className.contains("UIHostingController") { return "UIHostingController" }
            if className.contains("PlatformView") { return "PlatformView" }
            if className.contains("ViewHost") { return "ViewHost" }
            if className.contains("SwiftUI") {
                let components = className.components(separatedBy: ".")
                return components.last?.replacingOccurrences(of: "Host", with: "") ?? "SwiftUIView"
            }
            return className
        }

        @objc func dd_swizzledLayoutSubviews() {
            dd_swizzledLayoutSubviews() // calls original
            guard RenderTracker.shared.isEnabled, isSwiftUIHostingView else { return }

            let viewType = detectSwiftUIViewType()
            let identifier = "\(viewType)_\(ObjectIdentifier(self))"

            // DebugSwift's recursion guard — skip if overlay is active for this instance
            guard !RenderTracker.shared.activeOverlays.contains(identifier) else { return }

            RenderTracker.shared.recordRender(viewType)

            guard RenderTracker.shared.showOverlays, self.window != nil else { return }
            showRenderOverlay(viewType: viewType, identifier: identifier)
        }

        private func showRenderOverlay(viewType: String, identifier: String) {
            guard let window = self.window else { return }

            // Mark active to prevent recursion
            RenderTracker.shared.activeOverlays.insert(identifier)

            let viewFrame = convert(bounds, to: window)
            let overlay = UIView(frame: viewFrame)
            overlay.backgroundColor = .clear
            overlay.layer.borderColor = UIColor.systemOrange.cgColor
            overlay.layer.borderWidth = 1.0
            overlay.layer.cornerRadius = layer.cornerRadius
            overlay.isUserInteractionEnabled = false
            window.addSubview(overlay)

            // Render count badge
            let count = RenderTracker.shared._counts[viewType] ?? 0
            let badge = UILabel()
            badge.tag = 999
            badge.text = " \(count) "
            badge.font = .monospacedSystemFont(ofSize: 8, weight: .bold)
            badge.textColor = .white
            badge.backgroundColor = count <= 5 ? .systemGreen : count <= 20 ? .systemOrange : .systemRed
            badge.layer.cornerRadius = 3
            badge.clipsToBounds = true
            badge.textAlignment = .center
            badge.sizeToFit()
            badge.frame.origin = CGPoint(
                x: viewFrame.width - badge.frame.width - 5,
                y: 5
            )
            overlay.addSubview(badge)

            // Fade out and clean up — matches DebugSwift's transient overlay
            UIView.animate(withDuration: 1.0, animations: {
                overlay.alpha = 0
            }, completion: { _ in
                overlay.removeFromSuperview()
                RenderTracker.shared.activeOverlays.remove(identifier)
            })
        }
    }

    #endif

    // MARK: - Explicit opt-in modifier

    public struct RenderTrackingModifier: ViewModifier {
        let label: String

        public init(_ label: String) {
            self.label = label
        }

        public func body(content: Content) -> some View {
            let _ = RenderTracker.shared.recordRender(label)
            content
        }
    }

    public extension View {
        func trackRenders(_ label: String) -> some View {
            modifier(RenderTrackingModifier(label))
        }
    }

#endif
