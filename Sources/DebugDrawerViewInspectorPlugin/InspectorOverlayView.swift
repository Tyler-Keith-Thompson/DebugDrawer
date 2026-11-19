#if DEBUG && (os(macOS) || os(iOS))
    import Combine
    import SwiftUI

    /// A ripple where a click or touch landed, in an overlay's coordinates.
    struct Ripple: Identifiable, Equatable {
        let id: UUID
        let center: CGPoint
    }

    /// The grid's look, from the View Inspector's switches.
    struct GridStyle: Equatable {
        var spacing: CGFloat
        var color: Color
        var opacity: Double
    }

    /// What one overlay window draws: the app's views' outlines, the grids and the ripples, all
    /// in the overlay's coordinates.
    @MainActor
    final class InspectorOverlayModel: ObservableObject {
        @Published private(set) var outlines: [ViewOutline] = []
        @Published private(set) var grids: [CGRect] = []
        @Published private(set) var gridStyle = GridStyle(spacing: 8, color: .blue, opacity: 0.15)
        @Published private(set) var ripples: [Ripple] = []

        /// Takes the newest outlines and grids, publishing only what changed.
        ///
        /// - Returns: `true` when anything changed, so the overlay must be drawn again.
        @discardableResult
        func update(outlines: [ViewOutline], grids: [CGRect], gridStyle: GridStyle) -> Bool {
            var changed = false
            if self.outlines != outlines { self.outlines = outlines; changed = true }
            if self.grids != grids { self.grids = grids; changed = true }
            if self.gridStyle != gridStyle { self.gridStyle = gridStyle; changed = true }
            return changed
        }

        func addRipple(at center: CGPoint) {
            ripples.append(Ripple(id: UUID(), center: center))
        }

        func removeRipple(_ id: Ripple.ID) {
            ripples.removeAll { $0.id == id }
        }
    }

    /// The overlay window's content: follows its model.
    struct InspectorOverlayView: View {
        @ObservedObject var model: InspectorOverlayModel

        var body: some View {
            InspectorOverlayDrawing(
                outlines: model.outlines,
                grids: model.grids,
                gridStyle: model.gridStyle,
                ripples: model.ripples,
                rippleDidFinish: model.removeRipple
            )
        }
    }

    /// Outlines colored by depth, the alignment grid in each of its rectangles and a ripple at
    /// each click or touch, over a clear background, laid out from the top-leading corner.
    struct InspectorOverlayDrawing: View {
        let outlines: [ViewOutline]
        let grids: [CGRect]
        let gridStyle: GridStyle
        let ripples: [Ripple]
        let rippleDidFinish: (Ripple.ID) -> Void

        /// Depths cycle through this many hues.
        static let hueCount = 12

        var body: some View {
            ZStack(alignment: .topLeading) {
                ForEach(Array(grids.enumerated()), id: \.offset) { _, rect in
                    GridOverlayView(spacing: gridStyle.spacing, color: gridStyle.color, opacity: gridStyle.opacity)
                        .frame(width: rect.width, height: rect.height)
                        .clipped()
                        .offset(x: rect.minX, y: rect.minY)
                }
                Canvas { context, _ in
                    // One path per hue, so a window of many views is stroked a dozen times, not
                    // once per view.
                    for hue in 0 ..< Self.hueCount {
                        var path = Path()
                        for outline in outlines where outline.depth % Self.hueCount == hue {
                            if outline.covers.isEmpty {
                                // Inset by half the line, so the line lies inside the view, as a
                                // layer's border does.
                                path.addRect(outline.frame.insetBy(dx: 0.5, dy: 0.5))
                            } else {
                                for edge in outline.visibleEdges {
                                    path.move(to: edge.start)
                                    path.addLine(to: edge.end)
                                }
                            }
                        }
                        guard !path.isEmpty else { continue }
                        context.stroke(path, with: .color(Self.color(forDepth: hue)), lineWidth: 1)
                    }
                }
                ForEach(ripples) { ripple in
                    RippleView(center: ripple.center) { rippleDidFinish(ripple.id) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }

        /// The outline color of a view `depth` superviews deep: a hue per depth, twelve apart.
        static func color(forDepth depth: Int) -> Color {
            Color(hue: Double(depth % hueCount) / Double(hueCount), saturation: 0.8, brightness: 0.9, opacity: 0.6)
        }
    }

    /// A ripple where a click or touch landed, which grows and fades from the moment it appears,
    /// then reports it is done.
    struct RippleView: View {
        let center: CGPoint
        let didFinish: () -> Void
        @State private var progress = 0.0

        var body: some View {
            RippleMark(progress: progress)
                .position(center)
                .onAppear {
                    withAnimation(.easeOut(duration: 0.4)) {
                        progress = 1
                    } completion: {
                        didFinish()
                    }
                }
        }
    }

    /// A blue disc, 30 pt across, as it is `progress` of the way through its ripple: grown to
    /// 50 pt and faded out at 1. With Reduce Motion on it fades without growing.
    struct RippleMark: View {
        let progress: Double
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        private static let diameter: CGFloat = 30
        private static let grownDiameter: CGFloat = 50

        var body: some View {
            Circle()
                .fill(Color.blue.opacity(0.4))
                .overlay { Circle().strokeBorder(Color.blue.opacity(0.6), lineWidth: 2) }
                .frame(width: Self.diameter, height: Self.diameter)
                .scaleEffect(reduceMotion ? 1 : 1 + progress * (Self.grownDiameter / Self.diameter - 1))
                .opacity(1 - progress)
        }
    }
#endif
