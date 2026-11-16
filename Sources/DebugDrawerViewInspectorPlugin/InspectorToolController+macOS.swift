#if DEBUG && os(macOS)
    import AppKit
    import SwiftUI

    @MainActor
    public final class InspectorToolController: ObservableObject {
        public static let shared = InspectorToolController()

        public enum Mode: Equatable {
            case off
            case measure
            case inspect
        }

        @Published public var mode: Mode = .off {
            didSet {
                if mode != .off {
                    showOverlayWindow()
                } else {
                    hideOverlayWindow()
                }
            }
        }

        @Published public var selectedAttributes: [AttributeRow] = []
        @Published public var lastMeasureResult: MeasureResult?

        private var overlayWindow: InspectorOverlayWindow?
        private var highlightViews: [NSView] = []
        private var measureFirstView: NSView?

        public struct AttributeRow: Identifiable {
            public let id = UUID()
            public let label: String
            public let value: String
        }

        public struct MeasureResult {
            public let horizontal: CGFloat
            public let vertical: CGFloat
            public let diagonal: CGFloat
        }

        private init() {}

        public func clearPreviousSession() {
            clearHighlights()
            lastMeasureResult = nil
            selectedAttributes = []
            measureFirstView = nil
        }

        // MARK: - Overlay window

        private func showOverlayWindow() {
            guard let mainWindow = NSApp?.keyWindow else { return }
            hideOverlayWindow()

            let overlay = InspectorOverlayWindow(parentWindow: mainWindow, controller: self)
            mainWindow.addChildWindow(overlay, ordered: .above)
            overlay.makeKeyAndOrderFront(nil)
            overlayWindow = overlay

            // Change cursor to crosshair
            NSCursor.crosshair.push()
        }

        private func hideOverlayWindow() {
            overlayWindow?.orderOut(nil)
            overlayWindow?.parent?.removeChildWindow(overlayWindow!)
            overlayWindow = nil
            NSCursor.pop()
        }

        // MARK: - Handle click from overlay

        func handleOverlayClick(at screenPoint: NSPoint) {
            guard let mainWindow = overlayWindow?.parent,
                  let contentView = mainWindow.contentView
            else { return }

            let windowPoint = mainWindow.convertPoint(fromScreen: screenPoint)
            guard let hitView = contentView.hitTest(windowPoint) else { return }

            switch mode {
            case .measure:
                handleMeasureClick(hitView, in: mainWindow)
            case .inspect:
                handleInspectClick(hitView, in: mainWindow)
            case .off:
                break
            }
        }

        // MARK: - Inspect

        private func handleInspectClick(_ view: NSView, in window: NSWindow) {
            clearHighlights()
            selectedAttributes = buildAttributes(for: view)
            highlightView(view, color: .systemBlue, in: window)
            mode = .off
        }

        // MARK: - Measure

        private func handleMeasureClick(_ view: NSView, in window: NSWindow) {
            if measureFirstView == nil {
                clearHighlights()
                measureFirstView = view
                highlightView(view, color: .systemGreen, in: window)
            } else {
                highlightView(view, color: .systemOrange, in: window)
                calculateMeasurement(viewA: measureFirstView!, viewB: view, in: window)
                measureFirstView = nil
                mode = .off
            }
        }

        private func calculateMeasurement(viewA: NSView, viewB: NSView, in window: NSWindow) {
            guard let contentView = window.contentView else { return }

            let rectA = viewA.convert(viewA.bounds, to: contentView)
            let rectB = viewB.convert(viewB.bounds, to: contentView)

            let horizontal = edgeDistance(rectA, rectB, horizontal: true)
            let vertical = edgeDistance(rectA, rectB, horizontal: false)

            lastMeasureResult = MeasureResult(
                horizontal: horizontal, vertical: vertical,
                diagonal: sqrt(horizontal * horizontal + vertical * vertical)
            )

            // Draw measurement line
            let lineView = MeasurementLineView(
                from: CGPoint(x: rectA.midX, y: rectA.midY),
                to: CGPoint(x: rectB.midX, y: rectB.midY),
                horizontal: horizontal, vertical: vertical
            )
            lineView.frame = contentView.bounds
            lineView.wantsLayer = true
            contentView.addSubview(lineView, positioned: .above, relativeTo: nil)
            highlightViews.append(lineView)
        }

        private func edgeDistance(_ first: CGRect, _ second: CGRect, horizontal: Bool) -> CGFloat {
            if horizontal {
                if first.maxX <= second.minX { return second.minX - first.maxX }
                if second.maxX <= first.minX { return first.minX - second.maxX }
                return 0
            } else {
                if first.maxY <= second.minY { return second.minY - first.maxY }
                if second.maxY <= first.minY { return first.minY - second.maxY }
                return 0
            }
        }

        // MARK: - Highlights

        private func highlightView(_ view: NSView, color: NSColor, in window: NSWindow) {
            guard let contentView = window.contentView else { return }
            let rect = view.convert(view.bounds, to: contentView)

            let highlight = NSView(frame: rect)
            highlight.wantsLayer = true
            highlight.layer?.borderWidth = 3
            highlight.layer?.borderColor = color.withAlphaComponent(0.9).cgColor
            highlight.layer?.backgroundColor = color.withAlphaComponent(0.15).cgColor
            highlight.layer?.cornerRadius = 2
            contentView.addSubview(highlight, positioned: .above, relativeTo: nil)
            highlightViews.append(highlight)
        }

        private func clearHighlights() {
            for highlight in highlightViews {
                highlight.removeFromSuperview()
            }
            highlightViews.removeAll()
        }

        // MARK: - Attribute building

        private func buildAttributes(for view: NSView) -> [AttributeRow] {
            var attrs: [AttributeRow] = []
            let className = String(describing: type(of: view))

            attrs.append(AttributeRow(label: "Class", value: className))
            let frame = view.frame
            attrs.append(AttributeRow(
                label: "Frame",
                value: "\(Int(frame.origin.x)), \(Int(frame.origin.y)) — \(Int(frame.width))x\(Int(frame.height))"
            ))
            attrs.append(AttributeRow(label: "Bounds", value: "\(Int(view.bounds.width))x\(Int(view.bounds.height))"))
            attrs.append(AttributeRow(label: "Alpha", value: String(format: "%.2f", view.alphaValue)))
            attrs.append(AttributeRow(label: "Hidden", value: view.isHidden ? "Yes" : "No"))

            if let layer = view.layer {
                if layer.cornerRadius > 0 {
                    attrs.append(AttributeRow(label: "Corner Radius", value: "\(Int(layer.cornerRadius))"))
                }
                if layer.borderWidth > 0 {
                    attrs.append(AttributeRow(label: "Border", value: "\(layer.borderWidth)pt"))
                }
                if let bg = layer.backgroundColor, bg.alpha > 0.01 {
                    attrs.append(AttributeRow(label: "Background", value: NSColor(cgColor: bg)?.hexDescription ?? "—"))
                }
                if layer.masksToBounds {
                    attrs.append(AttributeRow(label: "Clips", value: "Yes"))
                }
            }

            if let label = view.accessibilityLabel(), !label.isEmpty {
                attrs.append(AttributeRow(label: "a11y Label", value: label))
            }
            if let role = view.accessibilityRole() {
                attrs.append(AttributeRow(label: "a11y Role", value: role.rawValue))
            }

            attrs.append(AttributeRow(label: "Constraints", value: "\(view.constraints.count)"))
            attrs.append(AttributeRow(label: "Subviews", value: "\(view.subviews.count)"))

            if let tf = view as? NSTextField {
                attrs.append(AttributeRow(label: "Text", value: String(tf.stringValue.prefix(50))))
                if let font = tf.font {
                    attrs.append(AttributeRow(label: "Font", value: "\(font.fontName) \(font.pointSize)pt"))
                }
            }
            if let btn = view as? NSButton {
                attrs.append(AttributeRow(label: "Title", value: btn.title))
            }

            return attrs
        }
    }

    // MARK: - Transparent click-catching overlay window

    final class InspectorOverlayWindow: NSWindow {
        weak var controller: InspectorToolController?

        init(parentWindow: NSWindow, controller: InspectorToolController) {
            self.controller = controller
            super.init(
                contentRect: parentWindow.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            isOpaque = false
            backgroundColor = .clear
            level = .floating
            hasShadow = false
            // Don't ignore mouse events — we WANT to catch clicks
            ignoresMouseEvents = false

            let trackingView = InspectorTrackingView(frame: parentWindow.contentView?.bounds ?? .zero)
            trackingView.overlayWindow = self
            contentView = trackingView
        }

        override var canBecomeKey: Bool {
            true
        }
    }

    /// The content view of the overlay window — catches mouse clicks.
    final class InspectorTrackingView: NSView {
        weak var overlayWindow: InspectorOverlayWindow?

        override func mouseDown(with event: NSEvent) {
            let screenPoint = overlayWindow?.convertPoint(toScreen: event.locationInWindow) ?? .zero
            overlayWindow?.controller?.handleOverlayClick(at: screenPoint)
        }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .crosshair)
        }
    }

    // MARK: - Measurement line view

    final class MeasurementLineView: NSView {
        let from: CGPoint
        let to: CGPoint
        let horizontal: CGFloat
        let vertical: CGFloat

        init(from: CGPoint, to: CGPoint, horizontal: CGFloat, vertical: CGFloat) {
            self.from = from
            self.to = to
            self.horizontal = horizontal
            self.vertical = vertical
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError()
        }

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            guard let ctx = NSGraphicsContext.current?.cgContext else { return }

            // Dashed line
            ctx.setStrokeColor(NSColor.systemYellow.withAlphaComponent(0.9).cgColor)
            ctx.setLineWidth(2)
            ctx.setLineDash(phase: 0, lengths: [6, 4])
            ctx.move(to: from)
            ctx.addLine(to: to)
            ctx.strokePath()

            // Labels
            let mid = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
            let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .bold)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.white,
                .backgroundColor: NSColor.black.withAlphaComponent(0.75)
            ]

            if horizontal > 0 {
                NSAttributedString(string: " H: \(Int(horizontal))pt ", attributes: attrs)
                    .draw(at: CGPoint(x: mid.x + 6, y: mid.y - 22))
            }
            if vertical > 0 {
                NSAttributedString(string: " V: \(Int(vertical))pt ", attributes: attrs)
                    .draw(at: CGPoint(x: mid.x + 6, y: mid.y + 6))
            }
        }
    }

    // MARK: - NSColor hex helper

    extension NSColor {
        var hexDescription: String {
            guard let rgb = usingColorSpace(.sRGB) else { return "—" }
            return String(format: "#%02X%02X%02X",
                          Int(rgb.redComponent * 255),
                          Int(rgb.greenComponent * 255),
                          Int(rgb.blueComponent * 255))
        }
    }
#endif
