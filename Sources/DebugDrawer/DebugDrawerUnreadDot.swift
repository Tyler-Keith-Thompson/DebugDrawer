import SwiftUI

/// The dot Mail and Xcode put beside what hasn't been looked at yet: a small circle in the accent
/// color. Put it before a row's title for an item the developer hasn't opened.
///
/// VoiceOver reads it as "Unread"; where a word beside it says the same, hide it with
/// `accessibilityHidden(true)`.
///
/// The type exists in every build so a plugin's body compiles unchanged in release, where it
/// draws nothing.
public struct DebugDrawerUnreadDot: View {
    /// An unread dot.
    public init() {}

    public var body: some View {
        #if DEBUG
            DrawerUnreadDotFace()
        #else
            EmptyView()
        #endif
    }
}

#if DEBUG
    /// The unread dot's face, the size of the navigator tabs' dot, growing with the text.
    struct DrawerUnreadDotFace: View {
        @ScaledMetric(relativeTo: .body) private var size = DrawerSpacing.unreadDot

        var body: some View {
            Circle()
                .fill(DrawerPalette.accent)
                .frame(width: size, height: size)
                .accessibilityElement()
                .accessibilityLabel("Unread")
        }
    }
#endif
