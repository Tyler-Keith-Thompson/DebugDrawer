#if DEBUG
    import AppKit
    import ObjectiveC
    import SwiftUI

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
        @Published public private(set) var renderCounts: [String: Int] = [:]
        @Published public private(set) var lastRenderTimes: [String: Date] = [:]

        var activeOverlays: Set<String> = []
        private var swizzled = false

        private init() {}

        public func recordRender(_ id: String) {
            guard isEnabled else { return }
            renderCounts[id, default: 0] += 1
            lastRenderTimes[id] = Date()
        }

        public func reset() {
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
        }

        private func swizzleMethod(cls: AnyClass, original: Selector, swizzled: Selector) {
            guard let originalMethod = class_getInstanceMethod(cls, original),
                  let swizzledMethod = class_getInstanceMethod(cls, swizzled)
            else { return }
            method_exchangeImplementations(originalMethod, swizzledMethod)
        }
    }

    // MARK: - Swizzled methods

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

        fileprivate func extractViewTypeName() -> String {
            let fullName = String(describing: type(of: self))

            // Try to extract meaningful name from generic parameters
            // e.g., "NSHostingView<ModifiedContent<ContentView, ...>>" → "ContentView"
            // Look for the first non-framework type name
            let patterns = [
                // Match "ContentView" from "NSHostingView<ModifiedContent<ContentView, ..."
                "(?<=<)[A-Z][A-Za-z]+(?=View[,>])",
                // Match any CamelCase name between < and ,
                "(?<=<)[A-Z][A-Za-z]{2,}(?=[,>])",
                // Match last CamelCase word before >
                "([A-Z][a-z]+)+(?=>)",
            ]

            for pattern in patterns {
                if let range = fullName.range(of: pattern, options: .regularExpression) {
                    let match = String(fullName[range])
                    // Skip framework-internal names
                    if !match.hasPrefix("Modified") && !match.hasPrefix("_") &&
                        !match.hasPrefix("Environment") && !match.hasPrefix("Optional") &&
                        match != "SheetContent"
                    {
                        return match
                    }
                }
            }

            return fullName.components(separatedBy: ".").last ?? fullName
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

            let viewType = extractViewTypeName()
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

            let viewType = extractViewTypeName()
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
