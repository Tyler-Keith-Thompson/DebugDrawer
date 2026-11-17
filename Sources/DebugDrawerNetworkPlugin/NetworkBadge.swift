#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// A word in a hairline box in the accent color, beside a request's status, that says the
    /// plugin had a hand in the answer, so it never passes for the server's own.
    struct NetworkBadge: View {
        let title: String
        @ScaledMetric(relativeTo: .body) private var padding: CGFloat = 4

        init(_ title: String) {
            self.title = title
        }

        var body: some View {
            Text(title)
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

    /// "Mocked", beside the status of a request a mock rule answered.
    struct NetworkMockedBadge: View {
        var body: some View {
            NetworkBadge("Mocked")
        }
    }

    /// "Conditioned", beside the status of a request a conditioning profile slowed or failed.
    struct NetworkConditionedBadge: View {
        var body: some View {
            NetworkBadge("Conditioned")
        }
    }
#endif
