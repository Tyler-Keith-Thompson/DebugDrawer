#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The offset from the window's top-leading corner, a point at a time, and Move, which moves
    /// it by dragging.
    struct MockupPositionSection: View {
        @Binding var offset: CGSize
        @Binding var isMoving: Bool
        /// Whether the mockup shows; Move needs it to.
        let isVisible: Bool

        var body: some View {
            DebugDrawerSection("Position") {
                DebugDrawerRow("X", systemImage: "arrow.left.and.right") {
                    OffsetStepper(axis: "X", value: $offset.width)
                }
                DebugDrawerRow("Y", systemImage: "arrow.up.and.down") {
                    OffsetStepper(axis: "Y", value: $offset.height)
                }
                DebugDrawerRow("Move by Dragging", systemImage: "hand.draw", isOn: $isMoving)
                    .disabled(!isVisible)
                    .accessibilityHint("While on, the mockup takes every touch, and a drag moves it")
            } footer: {
                Text("While Move is on, the mockup takes every touch: drag anywhere in the window, then tap Done.")
            }
        }
    }

    /// The offset along one axis in points, with a stepper that moves it a point at a time.
    struct OffsetStepper: View {
        let axis: String
        @Binding var value: CGFloat

        var body: some View {
            HStack(spacing: 8) {
                Text("\(Int(value.rounded())) pt")
                    .debugDrawerFont(.value)
                    .debugDrawerForegroundStyle(.secondary)
                    .fixedSize()
                    .accessibilityHidden(true)
                Stepper("\(axis) offset", value: $value, in: DesignOverlaySettings.offsetRange, step: 1)
                    .labelsHidden()
                    .accessibilityLabel("\(axis) offset")
                    .accessibilityValue("\(Int(value.rounded())) points")
            }
        }
    }
#endif
