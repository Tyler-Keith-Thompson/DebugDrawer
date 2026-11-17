#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// Shown at the window's bottom leading corner while Move is on: that a drag moves the mockup,
    /// where it is, and Done. The mockup takes every touch then, the app's own controls included,
    /// so this is the way out with the drawer closed and the HUD unpinned.
    struct MoveModeBar: View {
        let offset: CGSize
        let done: () -> Void

        var body: some View {
            HStack(spacing: 12) {
                Image(systemName: "hand.draw")
                    .accessibilityHidden(true)
                Text("Drag to move the mockup")
                    .debugDrawerFont(.body)
                Text(offset.pointsText)
                    .debugDrawerFont(.value)
                    .debugDrawerForegroundStyle(.secondary)
                    .accessibilityLabel("Offset \(offset.pointsText)")
                Button("Done", action: done)
                    .debugDrawerButtonStyle(.primary)
                    .accessibilityLabel("Done moving the mockup")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .accessibilityElement(children: .contain)
        }
    }

    extension CGSize {
        /// The offset in whole points, "x 12  y -4".
        var pointsText: String {
            "x \(Int(width.rounded()))  y \(Int(height.rounded()))"
        }
    }
#endif
