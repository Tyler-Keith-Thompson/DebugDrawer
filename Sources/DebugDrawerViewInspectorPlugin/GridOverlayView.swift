#if DEBUG
    import SwiftUI

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
                    for lineX in [centerX + offset, centerX - offset] where lineX >= 0 && lineX <= size.width {
                        context.stroke(
                            Path { path in path.move(to: .init(x: lineX, y: 0)); path.addLine(to: .init(x: lineX, y: size.height)) },
                            with: .color(lineColor),
                            lineWidth: 0.5
                        )
                    }
                    offset += spacing
                }

                // Horizontal lines
                offset = 0
                while centerY + offset <= size.height || centerY - offset >= 0 {
                    for lineY in [centerY + offset, centerY - offset] where lineY >= 0 && lineY <= size.height {
                        context.stroke(
                            Path { path in path.move(to: .init(x: 0, y: lineY)); path.addLine(to: .init(x: size.width, y: lineY)) },
                            with: .color(lineColor),
                            lineWidth: 0.5
                        )
                    }
                    offset += spacing
                }

                // Center crosshair (slightly brighter)
                let crossColor = color.opacity(min(opacity * 2, 0.5))
                context.stroke(
                    Path { path in path.move(to: .init(x: centerX, y: 0)); path.addLine(to: .init(x: centerX, y: size.height)) },
                    with: .color(crossColor),
                    lineWidth: 1
                )
                context.stroke(
                    Path { path in path.move(to: .init(x: 0, y: centerY)); path.addLine(to: .init(x: size.width, y: centerY)) },
                    with: .color(crossColor),
                    lineWidth: 1
                )

                // Dimension labels at top-right
                let dimText = "\(Int(size.width))x\(Int(size.height))"
                context.draw(
                    Text(dimText).font(.system(.caption2, design: .monospaced)).foregroundColor(color.opacity(0.4)),
                    at: CGPoint(x: size.width - 40, y: 12)
                )
            }
            .allowsHitTesting(false)
            .ignoresSafeArea()
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
#endif
