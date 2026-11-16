#if DEBUG
    import SwiftUI

    /// A section's heading, read by VoiceOver as one.
    struct NotificationsSectionHeading: View {
        let title: String

        var body: some View {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
        }
    }
#endif
