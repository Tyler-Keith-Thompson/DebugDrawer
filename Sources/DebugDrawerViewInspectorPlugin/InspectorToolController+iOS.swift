#if DEBUG && os(iOS)
    import SwiftUI
    import UIKit

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
                    showOverlayView()
                } else {
                    hideOverlayView()
                }
            }
        }

        @Published public var selectedAttributes: [AttributeRow] = []
        @Published public var lastMeasureResult: MeasureResult?

        private var overlayView: InspectorOverlayView?
        private var highlightViews: [UIView] = []
        private var measureFirstView: UIView?

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

        // MARK: - Overlay view

        private func showOverlayView() {
            guard let window = ViewBorderController.keyWindow else { return }
            hideOverlayView()

            let overlay = InspectorOverlayView(frame: window.bounds, controller: self)
            overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            window.addSubview(overlay)
            overlayView = overlay
        }

        private func hideOverlayView() {
            overlayView?.removeFromSuperview()
            overlayView = nil
        }

        // MARK: - Handle tap from overlay

        func handleOverlayTap(at point: CGPoint) {
            guard let window = ViewBorderController.keyWindow,
                  let rootView = window.rootViewController?.view
            else { return }

            // Convert from overlay coordinates to window coordinates
            let windowPoint = overlayView?.convert(point, to: window) ?? point
            guard let hitView = rootView.hitTest(windowPoint, with: nil),
                  hitView !== overlayView
            else { return }

            switch mode {
            case .measure:
                handleMeasureTap(hitView, in: window)
            case .inspect:
                handleInspectTap(hitView, in: window)
            case .off:
                break
            }
        }

        // MARK: - Inspect

        private func handleInspectTap(_ view: UIView, in window: UIWindow) {
            clearHighlights()
            selectedAttributes = buildAttributes(for: view)
            highlightView(view, color: .systemBlue, in: window)
            mode = .off
        }

        // MARK: - Measure

        private func handleMeasureTap(_ view: UIView, in window: UIWindow) {
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

        private func calculateMeasurement(viewA: UIView, viewB: UIView, in window: UIWindow) {
            let rectA = viewA.convert(viewA.bounds, to: window)
            let rectB = viewB.convert(viewB.bounds, to: window)

            let horizontal = edgeDistance(rectA, rectB, horizontal: true)
            let vertical = edgeDistance(rectA, rectB, horizontal: false)

            lastMeasureResult = MeasureResult(
                horizontal: horizontal, vertical: vertical,
                diagonal: sqrt(horizontal * horizontal + vertical * vertical)
            )

            // Draw measurement line
            let lineView = MeasurementLineView(
                frame: window.bounds,
                from: CGPoint(x: rectA.midX, y: rectA.midY),
                to: CGPoint(x: rectB.midX, y: rectB.midY),
                horizontal: horizontal, vertical: vertical
            )
            lineView.isUserInteractionEnabled = false
            window.addSubview(lineView)
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

        private func highlightView(_ view: UIView, color: UIColor, in window: UIWindow) {
            let rect = view.convert(view.bounds, to: window)

            let highlight = UIView(frame: rect)
            highlight.layer.borderWidth = 3
            highlight.layer.borderColor = color.withAlphaComponent(0.9).cgColor
            highlight.layer.backgroundColor = color.withAlphaComponent(0.15).cgColor
            highlight.layer.cornerRadius = 2
            highlight.isUserInteractionEnabled = false
            window.addSubview(highlight)
            highlightViews.append(highlight)
        }

        private func clearHighlights() {
            for highlight in highlightViews {
                highlight.removeFromSuperview()
            }
            highlightViews.removeAll()
        }

        // MARK: - Attribute building

        private func buildAttributes(for view: UIView) -> [AttributeRow] {
            var attrs: [AttributeRow] = []
            let className = String(describing: type(of: view))

            attrs.append(AttributeRow(label: "Class", value: className))
            let frame = view.frame
            attrs.append(AttributeRow(
                label: "Frame",
                value: "\(Int(frame.origin.x)), \(Int(frame.origin.y)) — \(Int(frame.width))x\(Int(frame.height))"
            ))
            attrs.append(AttributeRow(label: "Bounds", value: "\(Int(view.bounds.width))x\(Int(view.bounds.height))"))
            attrs.append(AttributeRow(label: "Alpha", value: String(format: "%.2f", view.alpha)))
            attrs.append(AttributeRow(label: "Hidden", value: view.isHidden ? "Yes" : "No"))

            let layer = view.layer
            if layer.cornerRadius > 0 {
                attrs.append(AttributeRow(label: "Corner Radius", value: "\(Int(layer.cornerRadius))"))
            }
            if layer.borderWidth > 0 {
                attrs.append(AttributeRow(label: "Border", value: "\(layer.borderWidth)pt"))
            }
            if let bg = layer.backgroundColor, bg.alpha > 0.01 {
                attrs.append(AttributeRow(label: "Background", value: UIColor(cgColor: bg).hexDescription))
            }
            if layer.masksToBounds {
                attrs.append(AttributeRow(label: "Clips", value: "Yes"))
            }

            if let label = view.accessibilityLabel, !label.isEmpty {
                attrs.append(AttributeRow(label: "a11y Label", value: label))
            }
            if view.accessibilityTraits != .none {
                attrs.append(AttributeRow(label: "a11y Traits", value: describeTraits(view.accessibilityTraits)))
            }

            attrs.append(AttributeRow(label: "Constraints", value: "\(view.constraints.count)"))
            attrs.append(AttributeRow(label: "Subviews", value: "\(view.subviews.count)"))

            if let label = view as? UILabel {
                attrs.append(AttributeRow(label: "Text", value: String((label.text ?? "").prefix(50))))
                if let font = label.font {
                    attrs.append(AttributeRow(label: "Font", value: "\(font.fontName) \(font.pointSize)pt"))
                }
            }
            if let btn = view as? UIButton {
                attrs.append(AttributeRow(label: "Title", value: btn.titleLabel?.text ?? ""))
            }
            if let tf = view as? UITextField {
                attrs.append(AttributeRow(label: "Text", value: String((tf.text ?? "").prefix(50))))
            }

            return attrs
        }

        private func describeTraits(_ traits: UIAccessibilityTraits) -> String {
            var names: [String] = []
            if traits.contains(.button) { names.append("Button") }
            if traits.contains(.link) { names.append("Link") }
            if traits.contains(.header) { names.append("Header") }
            if traits.contains(.image) { names.append("Image") }
            if traits.contains(.selected) { names.append("Selected") }
            if traits.contains(.staticText) { names.append("StaticText") }
            if traits.contains(.adjustable) { names.append("Adjustable") }
            return names.isEmpty ? "None" : names.joined(separator: ", ")
        }
    }

    // MARK: - Transparent tap-catching overlay view

    final class InspectorOverlayView: UIView {
        weak var controller: InspectorToolController?

        init(frame: CGRect, controller: InspectorToolController) {
            self.controller = controller
            super.init(frame: frame)
            backgroundColor = UIColor.clear

            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            addGestureRecognizer(tap)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError()
        }

        @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
            let point = gesture.location(in: self)
            controller?.handleOverlayTap(at: point)
        }
    }

    // MARK: - Measurement line view

    final class MeasurementLineView: UIView {
        let from: CGPoint
        let to: CGPoint
        let horizontal: CGFloat
        let vertical: CGFloat

        init(frame: CGRect, from: CGPoint, to: CGPoint, horizontal: CGFloat, vertical: CGFloat) {
            self.from = from
            self.to = to
            self.horizontal = horizontal
            self.vertical = vertical
            super.init(frame: frame)
            backgroundColor = .clear
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError()
        }

        override func draw(_ rect: CGRect) {
            super.draw(rect)
            guard let ctx = UIGraphicsGetCurrentContext() else { return }

            // Dashed line
            ctx.setStrokeColor(UIColor.systemYellow.withAlphaComponent(0.9).cgColor)
            ctx.setLineWidth(2)
            ctx.setLineDash(phase: 0, lengths: [6, 4])
            ctx.move(to: from)
            ctx.addLine(to: to)
            ctx.strokePath()

            // Labels
            let mid = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
            let font = UIFont.monospacedSystemFont(ofSize: 11, weight: .bold)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor.white,
                .backgroundColor: UIColor.black.withAlphaComponent(0.75)
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

    // MARK: - UIColor hex helper

    extension UIColor {
        var hexDescription: String {
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            return String(format: "#%02X%02X%02X", Int(red * 255), Int(green * 255), Int(blue * 255))
        }
    }
#endif
