#if DEBUG
    import AppKit
    import Combine
    import DebugDrawer
    import SwiftUI

    // MARK: - Controller

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
                guard let view = notification.object as? NSView,
                      view.window == NSApp?.keyWindow else { return }
                Task { @MainActor [weak self] in
                    guard let self, self.isBordersEnabled else { return }
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

    // MARK: - Grid overlay

    struct GridOverlayView: View {
        let spacing: CGFloat
        let color: Color
        let opacity: Double

        var body: some View {
            Canvas { context, size in
                let lineColor = color.opacity(opacity)
                let centerX = size.width / 2
                let centerY = size.height / 2

                // Draw from center outward for symmetry
                // Vertical lines
                var offset: CGFloat = 0
                while centerX + offset <= size.width || centerX - offset >= 0 {
                    for x in [centerX + offset, centerX - offset] where x >= 0 && x <= size.width {
                        context.stroke(
                            Path { p in p.move(to: .init(x: x, y: 0)); p.addLine(to: .init(x: x, y: size.height)) },
                            with: .color(lineColor),
                            lineWidth: 0.5
                        )
                    }
                    offset += spacing
                }

                // Horizontal lines
                offset = 0
                while centerY + offset <= size.height || centerY - offset >= 0 {
                    for y in [centerY + offset, centerY - offset] where y >= 0 && y <= size.height {
                        context.stroke(
                            Path { p in p.move(to: .init(x: 0, y: y)); p.addLine(to: .init(x: size.width, y: y)) },
                            with: .color(lineColor),
                            lineWidth: 0.5
                        )
                    }
                    offset += spacing
                }

                // Center crosshair (slightly brighter)
                let crossColor = color.opacity(min(opacity * 2, 0.5))
                context.stroke(
                    Path { p in p.move(to: .init(x: centerX, y: 0)); p.addLine(to: .init(x: centerX, y: size.height)) },
                    with: .color(crossColor),
                    lineWidth: 1
                )
                context.stroke(
                    Path { p in p.move(to: .init(x: 0, y: centerY)); p.addLine(to: .init(x: size.width, y: centerY)) },
                    with: .color(crossColor),
                    lineWidth: 1
                )

                // Dimension labels at top-right
                let dimText = "\(Int(size.width))×\(Int(size.height))"
                context.draw(
                    Text(dimText).font(.system(size: 9, design: .monospaced)).foregroundColor(color.opacity(0.4)),
                    at: CGPoint(x: size.width - 40, y: 12)
                )
            }
            .allowsHitTesting(false)
            .ignoresSafeArea()
        }
    }

    // MARK: - View hierarchy model

    struct ViewNode: Identifiable {
        let id = UUID()
        let className: String
        let frame: NSRect
        let accessibilityLabel: String?
        let accessibilityRole: String?
        let isHidden: Bool
        let alpha: CGFloat
        let hasClipping: Bool
        let cornerRadius: CGFloat
        let backgroundColor: String?
        let constraintCount: Int
        let subviewCount: Int
        let children: [ViewNode]

        @MainActor static func build(from view: NSView, maxDepth: Int = 12) -> ViewNode {
            let children: [ViewNode]
            if maxDepth > 0 {
                children = view.subviews.map { build(from: $0, maxDepth: maxDepth - 1) }
            } else {
                children = []
            }

            let bgColor: String? = if let bg = view.layer?.backgroundColor {
                NSColor(cgColor: bg)?.hexString
            } else {
                nil
            }

            return ViewNode(
                className: String(describing: type(of: view)),
                frame: view.frame,
                accessibilityLabel: view.accessibilityLabel(),
                accessibilityRole: view.accessibilityRole()?.rawValue,
                isHidden: view.isHidden,
                alpha: CGFloat(view.alphaValue),
                hasClipping: view.layer?.masksToBounds ?? false,
                cornerRadius: view.layer?.cornerRadius ?? 0,
                backgroundColor: bgColor,
                constraintCount: view.constraints.count,
                subviewCount: view.subviews.count,
                children: children
            )
        }
    }

    private extension NSColor {
        var hexString: String? {
            guard let rgb = usingColorSpace(.sRGB) else { return nil }
            let r = Int(rgb.redComponent * 255)
            let g = Int(rgb.greenComponent * 255)
            let b = Int(rgb.blueComponent * 255)
            return String(format: "#%02X%02X%02X", r, g, b)
        }
    }

    // MARK: - Plugin

    public struct ViewInspectorPlugin: DebugDrawerPlugin {
        public var title = "View Inspector"
        public var icon = "rectangle.dashed"

        public init() {}

        public var body: some View {
            ViewInspectorPluginView()
        }
    }

    struct ViewInspectorPluginView: View {
        @ObservedObject private var controller = ViewBorderController.shared
        @ObservedObject private var renderTracker = RenderTracker.shared
        @ObservedObject private var inspectorTool = InspectorToolController.shared
        @State private var hierarchy: ViewNode?
        @State private var isHierarchyExpanded = false
        @State private var searchText = ""
        @State private var debugger3DRequest: ViewDebugger3DRequest?

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                // --- Visual overlays ---
                Toggle("View Borders", isOn: $controller.isBordersEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)

                Toggle("Alignment Grid", isOn: $controller.isGridEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)

                if controller.isGridEnabled {
                    HStack(spacing: 6) {
                        Text("\(Int(controller.gridSpacing))pt")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 28)
                        Slider(value: $controller.gridSpacing, in: 4 ... 32, step: 4)
                            .controlSize(.small)

                        Picker(selection: $controller.gridColor) {
                            ForEach(ViewBorderController.GridColor.allCases, id: \.self) { c in
                                Circle()
                                    .fill(c.color)
                                    .frame(width: 8, height: 8)
                                    .tag(c)
                            }
                        } label: { EmptyView() }
                            .pickerStyle(.segmented)
                            .frame(width: 100)
                            .controlSize(.mini)
                    }

                    HStack {
                        Text("Opacity")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Slider(value: $controller.gridOpacity, in: 0.05 ... 0.5)
                            .controlSize(.small)
                    }
                }

                Toggle("Click Indicators", isOn: $controller.isClickIndicatorEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)

                Divider()

                Divider()

                // --- Animation speed ---
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Animation Speed")
                            .font(.caption.weight(.medium))
                        Spacer()
                        Text(controller.animationSpeed == 1.0 ? "Normal" : "\(controller.animationSpeed, specifier: "%.1f")x")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $controller.animationSpeed, in: 1 ... 10, step: 0.5)
                        .controlSize(.small)
                }

                Divider()

                // --- SwiftUI Render Tracking ---
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Render Tracking", isOn: $renderTracker.isEnabled)
                        .toggleStyle(.switch)
                        .controlSize(.small)

                    if renderTracker.isEnabled {
                        Toggle("Show Overlays", isOn: $renderTracker.showOverlays)
                            .toggleStyle(.switch)
                            .controlSize(.mini)

                        if !renderTracker.renderCounts.isEmpty {
                            HStack {
                                Text("\(renderTracker.renderCounts.count) views, \(renderTracker.totalRenders) renders")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("Reset") { renderTracker.reset() }
                                    .font(.caption)
                                    .buttonStyle(.plain)
                                    .foregroundStyle(.secondary)
                            }

                            // Top re-renderers
                            VStack(alignment: .leading, spacing: 1) {
                                ForEach(renderTracker.sortedEntries.prefix(8), id: \.id) { entry in
                                    HStack {
                                        Text(entry.id)
                                            .font(.system(size: 9, design: .monospaced))
                                            .lineLimit(1)
                                        Spacer()
                                        Text("\(entry.count)")
                                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                                            .foregroundStyle(renderCountColor(entry.count))
                                    }
                                }
                            }
                            .padding(4)
                            .background(Color.primary.opacity(0.05))
                            .cornerRadius(3)
                        }
                    }
                }

                Divider()

                // --- View Hierarchy ---
                HStack {
                    Text("View Hierarchy")
                        .font(.caption.weight(.medium))
                    Spacer()

                    Button(isHierarchyExpanded ? "Collapse" : "Snapshot") {
                        if isHierarchyExpanded {
                            isHierarchyExpanded = false
                            hierarchy = nil
                        } else {
                            snapshotHierarchy()
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if isHierarchyExpanded, let root = hierarchy {
                    TextField("Filter...", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            hierarchyRow(root, depth: 0)
                        }
                    }
                    .frame(maxHeight: 250)
                    .background(Color.black.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            .sheet(item: $debugger3DRequest) { request in
                ViewDebugger3DCombinedSheet(targetView: request.targetView)
            }
        }

        private func toolButton(_ label: String, icon: String, mode: InspectorToolController.Mode) -> some View {
            Button(action: {
                inspectorTool.clearPreviousSession()
                inspectorTool.mode = inspectorTool.mode == mode ? .off : mode
            }) {
                HStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.system(size: 10))
                    Text(label)
                        .font(.caption)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(inspectorTool.mode == mode ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                .cornerRadius(4)
            }
            .buttonStyle(.plain)
        }

        private func open3DDebugger() {
            guard let view = NSApp?.keyWindow?.contentView else { return }
            debugger3DRequest = ViewDebugger3DRequest(targetView: view)
        }

        private func renderCountColor(_ count: Int) -> Color {
            if count <= 3 { return .green }
            if count <= 10 { return .orange }
            return .red
        }

        private func snapshotHierarchy() {
            guard let contentView = NSApp?.keyWindow?.contentView else { return }
            hierarchy = ViewNode.build(from: contentView)
            isHierarchyExpanded = true
        }

        private func matchesFilter(_ node: ViewNode) -> Bool {
            guard !searchText.isEmpty else { return true }
            let q = searchText.lowercased()
            return node.className.lowercased().contains(q)
                || (node.accessibilityLabel?.lowercased().contains(q) ?? false)
                || (node.accessibilityRole?.lowercased().contains(q) ?? false)
        }

        private func subtreeMatchesFilter(_ node: ViewNode) -> Bool {
            if matchesFilter(node) { return true }
            return node.children.contains(where: { subtreeMatchesFilter($0) })
        }

        private func hierarchyRow(_ node: ViewNode, depth: Int) -> AnyView {
            guard subtreeMatchesFilter(node) else { return AnyView(EmptyView()) }

            return AnyView(DisclosureGroup {
                ForEach(node.children) { child in
                    hierarchyRow(child, depth: depth + 1)
                }
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(node.className)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(node.accessibilityLabel != nil ? Color.accentColor : .primary)

                        if node.isHidden {
                            Text("HIDDEN")
                                .font(.system(size: 7, weight: .bold, design: .monospaced))
                                .foregroundStyle(.red)
                        }

                        if node.alpha < 1.0 {
                            Text("α\(node.alpha, specifier: "%.1f")")
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundStyle(.orange)
                        }

                        if node.hasClipping {
                            Text("CLIP")
                                .font(.system(size: 7, weight: .bold, design: .monospaced))
                                .foregroundStyle(.purple)
                        }
                    }

                    HStack(spacing: 6) {
                        Text("\(Int(node.frame.width))×\(Int(node.frame.height))")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.tertiary)

                        if node.cornerRadius > 0 {
                            Text("r\(Int(node.cornerRadius))")
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundStyle(.cyan)
                        }

                        if let bg = node.backgroundColor {
                            HStack(spacing: 2) {
                                Circle()
                                    .fill(Color(nsColor: NSColor(hex: bg)))
                                    .frame(width: 6, height: 6)
                                Text(bg)
                                    .font(.system(size: 8, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                            }
                        }

                        if let role = node.accessibilityRole {
                            Text(role)
                                .font(.system(size: 8, design: .monospaced))
                                .padding(.horizontal, 3)
                                .background(Color.purple.opacity(0.15))
                                .cornerRadius(2)
                        }

                        if let label = node.accessibilityLabel {
                            Text(label)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        if node.constraintCount > 0 {
                            Text("⚓\(node.constraintCount)")
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }

                        if node.subviewCount > 0 {
                            Text("(\(node.subviewCount))")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .padding(.vertical, 1)
            }
            .padding(.leading, CGFloat(depth) * 4))
        }
    }

    // MARK: - NSColor hex init (for bg color display)

    private extension NSColor {
        convenience init(hex: String) {
            var h = hex
            if h.hasPrefix("#") { h = String(h.dropFirst()) }
            guard h.count == 6, let val = UInt64(h, radix: 16) else {
                self.init(white: 0, alpha: 1)
                return
            }
            let r = CGFloat((val >> 16) & 0xFF) / 255.0
            let g = CGFloat((val >> 8) & 0xFF) / 255.0
            let b = CGFloat(val & 0xFF) / 255.0
            self.init(red: r, green: g, blue: b, alpha: 1)
        }
    }

    // MARK: - Grid modifier

    public struct DebugGridModifier: ViewModifier {
        @ObservedObject private var controller = ViewBorderController.shared

        public init() {}

        public func body(content: Content) -> some View {
            content
                .overlay {
                    if controller.isGridEnabled {
                        GridOverlayView(
                            spacing: controller.gridSpacing,
                            color: controller.gridColor.color,
                            opacity: controller.gridOpacity
                        )
                    }
                }
        }
    }

    public extension View {
        func debugGrid() -> some View {
            modifier(DebugGridModifier())
        }
    }

    // MARK: - Click indicator

    @MainActor
    final class ClickIndicatorMonitor {
        static let shared = ClickIndicatorMonitor()

        private var monitor: Any?
        private var overlayWindow: NSWindow?

        func start() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                self?.showRipple(for: event)
                return event
            }
        }

        func stop() {
            if let m = monitor {
                NSEvent.removeMonitor(m)
                monitor = nil
            }
            overlayWindow?.orderOut(nil)
            overlayWindow = nil
        }

        private func ensureOverlayWindow(for parentWindow: NSWindow) -> NSWindow {
            if let existing = overlayWindow, existing.parent == parentWindow {
                existing.setFrame(parentWindow.frame, display: false)
                return existing
            }
            overlayWindow?.orderOut(nil)

            let overlay = NSWindow(
                contentRect: parentWindow.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            overlay.isOpaque = false
            overlay.backgroundColor = .clear
            overlay.ignoresMouseEvents = true
            overlay.level = .floating
            overlay.hasShadow = false
            overlay.contentView = NSView(frame: parentWindow.frame)
            overlay.contentView?.wantsLayer = true

            parentWindow.addChildWindow(overlay, ordered: .above)
            overlayWindow = overlay
            return overlay
        }

        private func showRipple(for event: NSEvent) {
            guard let parentWindow = event.window else { return }
            let overlay = ensureOverlayWindow(for: parentWindow)
            guard let overlayContent = overlay.contentView else { return }

            // AppKit coordinates are bottom-left origin — no flip needed.
            let pointInWindow = event.locationInWindow
            let screenPoint = parentWindow.convertPoint(toScreen: pointInWindow)
            let overlayPoint = overlay.convertPoint(fromScreen: screenPoint)

            let size: CGFloat = 30
            let ripple = NSView(frame: NSRect(x: overlayPoint.x - size / 2, y: overlayPoint.y - size / 2, width: size, height: size))
            ripple.wantsLayer = true
            ripple.layer?.cornerRadius = size / 2
            ripple.layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.4).cgColor
            ripple.layer?.borderWidth = 2
            ripple.layer?.borderColor = NSColor.systemBlue.withAlphaComponent(0.6).cgColor
            overlayContent.addSubview(ripple)

            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.4
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                ripple.animator().alphaValue = 0
                ripple.animator().frame = ripple.frame.insetBy(dx: -10, dy: -10)
            } completionHandler: {
                ripple.removeFromSuperview()
            }
        }
    }

    // MARK: - Convenience installer

    public extension DebugDrawer {
        func installViewInspector() {
            registerGlobal(ViewInspectorPlugin())
        }
    }
#endif
