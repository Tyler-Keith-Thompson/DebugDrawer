#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The animation speed slider, from the windows' own speed to ten times slower, labelled with
    /// how much slower: "Normal", "2.5× slower", "10× slower".
    struct AnimationSpeedRow: View {
        /// How many times slower animations run: 1 to 10.
        @Binding var slowdown: Double

        var body: some View {
            DebugDrawerRow("Slow Animations") {
                Slider(value: $slowdown, in: 1 ... 10, step: 0.5)
                    .accessibilityLabel("Slow animations")
                    .accessibilityValue(Self.spokenLabel(for: slowdown))
            } accessory: {
                Text(Self.label(for: slowdown))
                    .debugDrawerFont(.value)
                    .accessibilityHidden(true)
            }
        }

        /// "Normal" at 1, otherwise how many times slower: "2.5× slower", "10× slower".
        static func label(for slowdown: Double) -> String {
            slowdown == 1 ? "Normal" : "\(slowdown.formatted(.number.precision(.fractionLength(0 ... 1))))× slower"
        }

        /// The label as VoiceOver reads it: "Normal speed", "10 times slower".
        static func spokenLabel(for slowdown: Double) -> String {
            slowdown == 1 ? "Normal speed" : "\(slowdown.formatted(.number.precision(.fractionLength(0 ... 1)))) times slower"
        }
    }
#endif
