#if DEBUG
    import Combine
    import SwiftUI

    /// Whether tracked views flash their frame when their body is evaluated.
    ///
    /// Apart from `RenderTracker`, so that a flash, which reads this, doesn't redraw each time the
    /// counts are published.
    @MainActor
    final class RenderFlashSetting: ObservableObject {
        /// The setting the plugin's Flash Renders row changes.
        static let shared = RenderFlashSetting()

        /// Off until the plugin turns it on.
        @Published var isOn = false
    }

    /// A tracked view's frame, drawn for a moment each time `trigger` changes, while flashes are on
    /// and Reduce Motion is off.
    ///
    /// It is its own view, so drawing and fading it evaluates only this body, never the tracked one.
    struct RenderFlash: View {
        /// Changes once per evaluation of the tracked body.
        let trigger: Int
        @ObservedObject private var setting = RenderFlashSetting.shared
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            if setting.isOn, !reduceMotion {
                Rectangle()
                    .strokeBorder(.orange, lineWidth: 2)
                    .keyframeAnimator(initialValue: 0.0, trigger: trigger) { frame, opacity in
                        frame.opacity(opacity)
                    } keyframes: { _ in
                        MoveKeyframe(1.0)
                        LinearKeyframe(0.0, duration: 0.6)
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
#endif
