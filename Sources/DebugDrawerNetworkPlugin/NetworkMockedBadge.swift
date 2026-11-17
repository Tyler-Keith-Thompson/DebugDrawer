#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// "Mocked" in a hairline box in the accent color, beside the status of a request a mock rule
    /// answered, so it never passes for the server's answer.
    struct NetworkMockedBadge: View {
        @ScaledMetric(relativeTo: .body) private var padding: CGFloat = 4

        var body: some View {
            Text("Mocked")
                .debugDrawerFont(.label)
                // One word: it never breaks across lines.
                .fixedSize()
                .padding(.horizontal, padding)
                .overlay {
                    // Stroked in the foreground style, the accent color set below.
                    RoundedRectangle(cornerRadius: 3).strokeBorder(lineWidth: 1)
                }
                .debugDrawerForegroundStyle(.accent)
        }
    }
#endif
